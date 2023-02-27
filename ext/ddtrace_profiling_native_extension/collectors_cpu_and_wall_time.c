#include <ruby.h>

#include "clock_id.h"
#include "collectors_cpu_and_wall_time.h"
#include "collectors_stack.h"
#include "helpers.h"
#include "libdatadog_helpers.h"
#include "private_vm_api_access.h"
#include "stack_recorder.h"
#include "time_helpers.h"

// Used to periodically sample threads, recording elapsed CPU-time and Wall-time between samples.
//
// This file implements the native bits of the Datadog::Profiling::Collectors::CpuAndWallTime class
//
// Triggering of this component (e.g. deciding when to take a sample) is implemented in Collectors::CpuAndWallTimeWorker.

// ---
// ## Tracking of cpu-time and wall-time spent during garbage collection
//
// This feature works by having an implicit state that a thread can be in: doing garbage collection. This state is
// tracked inside the thread's `per_thread_context.gc_tracking` data, and three functions, listed below. The functions
// will get called by the `Collectors::CpuAndWallTimeWorker` at very specific times in the VM lifetime.
//
// * `cpu_and_wall_time_collector_on_gc_start`: Called at the very beginning of the garbage collection process.
//   The internal VM `during_gc` flag is set to `true`, but Ruby has not done any work yet.
// * `cpu_and_wall_time_collector_on_gc_finish`: Called at the very end of the garbage collection process.
//   The internal VM `during_gc` flag is still set to `true`, but all the work has been done.
// * `cpu_and_wall_time_collector_sample_after_gc`: Called shortly after the garbage collection process.
//   The internal VM `during_gc` flag is set to `false`.
//
// Inside this component, here's what happens inside those three functions:
//
// When `cpu_and_wall_time_collector_on_gc_start` gets called, the current cpu and wall-time get recorded to the thread
// context: `cpu_time_at_gc_start_ns` and `wall_time_at_gc_start_ns`.
//
// While these fields are set, regular samples (if any) do not account for any time that passes after these two
// timestamps.
//
// (Regular samples can still account for the time between the previous sample and the start of GC.)
//
// When `cpu_and_wall_time_collector_on_gc_finish` gets called, the current cpu and wall-time again get recorded to the
// thread context: `cpu_time_at_gc_finish_ns` and `wall_time_at_gc_finish_ns`.
//
// Finally, when `cpu_and_wall_time_collector_sample_after_gc` gets called, the following happens:
//
// 1. A sample gets taken, using the special `SAMPLE_IN_GC` sample type, which produces a stack with a placeholder
// `Garbage Collection` frame as the latest frame. This sample gets assigned the cpu-time and wall-time period that was
// recorded between calls to `on_gc_start` and `on_gc_finish`.
//
// 2. The thread is no longer marked as being in gc (all gc tracking fields get reset back to `INVALID_TIME`).
//
// 3. The `cpu_time_at_previous_sample_ns` and `wall_time_at_previous_sample_ns` get updated with the elapsed time in
// GC, so that all time is accounted for -- e.g. the next sample will not get "blamed" by time spent in GC.
//
// In an earlier attempt at implementing this functionality (https://github.com/DataDog/dd-trace-rb/pull/2308), we
// discovered that we needed to factor the sampling work away from `cpu_and_wall_time_collector_on_gc_finish` and into a
// separate `cpu_and_wall_time_collector_sample_after_gc` because (as documented in more detail below),
// `sample_after_gc` could trigger memory allocation in rare occasions (usually exceptions), which is actually not
// allowed to happen during Ruby's garbage collection start/finish hooks.
// ---

#define INVALID_TIME -1
#define THREAD_ID_LIMIT_CHARS 44 // Why 44? "#{2**64} (#{2**64})".size + 1 for \0
#define IS_WALL_TIME true
#define IS_NOT_WALL_TIME false
#define MISSING_TRACER_CONTEXT_KEY 0

static ID at_active_span_id;  // id of :@active_span in Ruby
static ID at_active_trace_id; // id of :@active_trace in Ruby
static ID at_id_id;           // id of :@id in Ruby
static ID at_resource_id;     // id of :@resource in Ruby
static ID at_root_span_id;    // id of :@root_span in Ruby
static ID at_type_id;         // id of :@type in Ruby

// Contains state for a single CpuAndWallTime instance
struct cpu_and_wall_time_collector_state {
  // Note: Places in this file that usually need to be changed when this struct is changed are tagged with
  // "Update this when modifying state struct"

  // Required by Datadog::Profiling::Collectors::Stack as a scratch buffer during sampling
  sampling_buffer *sampling_buffer;
  // Hashmap <Thread Object, struct per_thread_context>
  st_table *hash_map_per_thread_context;
  // Datadog::Profiling::StackRecorder instance
  VALUE recorder_instance;
  // If the tracer is available and enabled, this will be the fiber-local symbol for accessing its running context,
  // to enable code hotspots and endpoint aggregation.
  // When not available, this is set to MISSING_TRACER_CONTEXT_KEY.
  ID tracer_context_key;
  // Track how many regular samples we've taken. Does not include garbage collection samples.
  // Currently **outside** of stats struct because we also use it to decide when to clean the contexts, and thus this
  // is not (just) a stat.
  unsigned int sample_count;
  // Reusable array to get list of threads
  VALUE thread_list_buffer;

  struct stats {
    // Track how many garbage collection samples we've taken.
    unsigned int gc_samples;
    // See cpu_and_wall_time_collector_on_gc_start for details
    unsigned int gc_samples_missed_due_to_missing_context;
  } stats;
};

// Tracks per-thread state
struct per_thread_context {
  char thread_id[THREAD_ID_LIMIT_CHARS];
  ddog_CharSlice thread_id_char_slice;
  thread_cpu_time_id thread_cpu_time_id;
  long cpu_time_at_previous_sample_ns;  // Can be INVALID_TIME until initialized or if getting it fails for another reason
  long wall_time_at_previous_sample_ns; // Can be INVALID_TIME until initialized

  struct {
    // Both of these fields are set by on_gc_start and kept until sample_after_gc is called.
    // Outside of this window, they will be INVALID_TIME.
    long cpu_time_at_start_ns;
    long wall_time_at_start_ns;

    // Both of these fields are set by on_gc_finish and kept until sample_after_gc is called.
    // Outside of this window, they will be INVALID_TIME.
    long cpu_time_at_finish_ns;
    long wall_time_at_finish_ns;
  } gc_tracking;
};

// Used to correlate profiles with traces
struct trace_identifiers {
  bool valid;
  uint64_t local_root_span_id;
  uint64_t span_id;
  VALUE trace_endpoint;
};

static void cpu_and_wall_time_collector_typed_data_mark(void *state_ptr);
static void cpu_and_wall_time_collector_typed_data_free(void *state_ptr);
static int hash_map_per_thread_context_mark(st_data_t key_thread, st_data_t _value, st_data_t _argument);
static int hash_map_per_thread_context_free_values(st_data_t _thread, st_data_t value_per_thread_context, st_data_t _argument);
static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(VALUE self, VALUE collector_instance, VALUE recorder_instance, VALUE max_frames, VALUE tracer_context_key);
static VALUE _native_sample(VALUE self, VALUE collector_instance, VALUE profiler_overhead_stack_thread);
static VALUE _native_on_gc_start(VALUE self, VALUE collector_instance);
static VALUE _native_on_gc_finish(VALUE self, VALUE collector_instance);
static VALUE _native_sample_after_gc(DDTRACE_UNUSED VALUE self, VALUE collector_instance);
void update_metrics_and_sample(
  struct cpu_and_wall_time_collector_state *state,
  VALUE thread_being_sampled,
  VALUE profiler_overhead_stack_thread,
  struct per_thread_context *thread_context,
  long current_cpu_time_ns,
  long current_monotonic_wall_time_ns
);
static void trigger_sample_for_thread(
  struct cpu_and_wall_time_collector_state *state,
  VALUE thread,
  VALUE stack_from_thread,
  struct per_thread_context *thread_context,
  sample_values values,
  sample_type type
);
static VALUE _native_thread_list(VALUE self);
static struct per_thread_context *get_or_create_context_for(VALUE thread, struct cpu_and_wall_time_collector_state *state);
static struct per_thread_context *get_context_for(VALUE thread, struct cpu_and_wall_time_collector_state *state);
static void initialize_context(VALUE thread, struct per_thread_context *thread_context);
static VALUE _native_inspect(VALUE self, VALUE collector_instance);
static VALUE per_thread_context_st_table_as_ruby_hash(struct cpu_and_wall_time_collector_state *state);
static int per_thread_context_as_ruby_hash(st_data_t key_thread, st_data_t value_context, st_data_t result_hash);
static VALUE stats_as_ruby_hash(struct cpu_and_wall_time_collector_state *state);
static void remove_context_for_dead_threads(struct cpu_and_wall_time_collector_state *state);
static int remove_if_dead_thread(st_data_t key_thread, st_data_t value_context, st_data_t _argument);
static VALUE _native_per_thread_context(VALUE self, VALUE collector_instance);
static long update_time_since_previous_sample(long *time_at_previous_sample_ns, long current_time_ns, long gc_start_time_ns, bool is_wall_time);
static long cpu_time_now_ns(struct per_thread_context *thread_context);
static long thread_id_for(VALUE thread);
static VALUE _native_stats(VALUE self, VALUE collector_instance);
static void trace_identifiers_for(struct cpu_and_wall_time_collector_state *state, VALUE thread, struct trace_identifiers *trace_identifiers_result);
static bool is_type_web(VALUE root_span_type);
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE collector_instance);
static VALUE thread_list(struct cpu_and_wall_time_collector_state *state);

void collectors_cpu_and_wall_time_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_cpu_and_wall_time_class = rb_define_class_under(collectors_module, "CpuAndWallTime", rb_cObject);
  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(collectors_cpu_and_wall_time_class, "Testing");

  // Instances of the CpuAndWallTime class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the cpu_and_wall_time_collector_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(collectors_cpu_and_wall_time_class, _native_new);

  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_initialize", _native_initialize, 4);
  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_inspect", _native_inspect, 1);
  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_reset_after_fork", _native_reset_after_fork, 1);
  rb_define_singleton_method(testing_module, "_native_sample", _native_sample, 2);
  rb_define_singleton_method(testing_module, "_native_on_gc_start", _native_on_gc_start, 1);
  rb_define_singleton_method(testing_module, "_native_on_gc_finish", _native_on_gc_finish, 1);
  rb_define_singleton_method(testing_module, "_native_sample_after_gc", _native_sample_after_gc, 1);
  rb_define_singleton_method(testing_module, "_native_thread_list", _native_thread_list, 0);
  rb_define_singleton_method(testing_module, "_native_per_thread_context", _native_per_thread_context, 1);
  rb_define_singleton_method(testing_module, "_native_stats", _native_stats, 1);

  at_active_span_id = rb_intern_const("@active_span");
  at_active_trace_id = rb_intern_const("@active_trace");
  at_id_id = rb_intern_const("@id");
  at_resource_id = rb_intern_const("@resource");
  at_root_span_id = rb_intern_const("@root_span");
  at_type_id = rb_intern_const("@type");
}

// This structure is used to define a Ruby object that stores a pointer to a struct cpu_and_wall_time_collector_state
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t cpu_and_wall_time_collector_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Collectors::CpuAndWallTime",
  .function = {
    .dmark = cpu_and_wall_time_collector_typed_data_mark,
    .dfree = cpu_and_wall_time_collector_typed_data_free,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    //.dcompact = NULL, // FIXME: Add support for compaction
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

// This function is called by the Ruby GC to give us a chance to mark any Ruby objects that we're holding on to,
// so that they don't get garbage collected
static void cpu_and_wall_time_collector_typed_data_mark(void *state_ptr) {
  struct cpu_and_wall_time_collector_state *state = (struct cpu_and_wall_time_collector_state *) state_ptr;

  // Update this when modifying state struct
  rb_gc_mark(state->recorder_instance);
  st_foreach(state->hash_map_per_thread_context, hash_map_per_thread_context_mark, 0 /* unused */);
  rb_gc_mark(state->thread_list_buffer);
}

static void cpu_and_wall_time_collector_typed_data_free(void *state_ptr) {
  struct cpu_and_wall_time_collector_state *state = (struct cpu_and_wall_time_collector_state *) state_ptr;

  // Update this when modifying state struct

  // Important: Remember that we're only guaranteed to see here what's been set in _native_new, aka
  // pointers that have been set NULL there may still be NULL here.
  if (state->sampling_buffer != NULL) sampling_buffer_free(state->sampling_buffer);

  // Free each entry in the map
  st_foreach(state->hash_map_per_thread_context, hash_map_per_thread_context_free_values, 0 /* unused */);
  // ...and then the map
  st_free_table(state->hash_map_per_thread_context);

  ruby_xfree(state);
}

// Mark Ruby thread references we keep as keys in hash_map_per_thread_context
static int hash_map_per_thread_context_mark(st_data_t key_thread, DDTRACE_UNUSED st_data_t _value, DDTRACE_UNUSED st_data_t _argument) {
  VALUE thread = (VALUE) key_thread;
  rb_gc_mark(thread);
  return ST_CONTINUE;
}

// Used to clear each of the per_thread_contexts inside the hash_map_per_thread_context
static int hash_map_per_thread_context_free_values(DDTRACE_UNUSED st_data_t _thread, st_data_t value_per_thread_context, DDTRACE_UNUSED st_data_t _argument) {
  struct per_thread_context *per_thread_context = (struct per_thread_context*) value_per_thread_context;
  ruby_xfree(per_thread_context);
  return ST_CONTINUE;
}

static VALUE _native_new(VALUE klass) {
  struct cpu_and_wall_time_collector_state *state = ruby_xcalloc(1, sizeof(struct cpu_and_wall_time_collector_state));

  // Update this when modifying state struct
  state->sampling_buffer = NULL;
  state->hash_map_per_thread_context =
   // "numtable" is an awful name, but TL;DR it's what should be used when keys are `VALUE`s.
    st_init_numtable();
  state->recorder_instance = Qnil;
  state->tracer_context_key = MISSING_TRACER_CONTEXT_KEY;
  state->thread_list_buffer = rb_ary_new();

  return TypedData_Wrap_Struct(klass, &cpu_and_wall_time_collector_typed_data, state);
}

static VALUE _native_initialize(DDTRACE_UNUSED VALUE _self, VALUE collector_instance, VALUE recorder_instance, VALUE max_frames, VALUE tracer_context_key) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  int max_frames_requested = NUM2INT(max_frames);
  if (max_frames_requested < 0) rb_raise(rb_eArgError, "Invalid max_frames: value must not be negative");

  // Update this when modifying state struct
  state->sampling_buffer = sampling_buffer_new(max_frames_requested);
  // hash_map_per_thread_context is already initialized, nothing to do here
  state->recorder_instance = enforce_recorder_instance(recorder_instance);

  if (RTEST(tracer_context_key)) {
    ENFORCE_TYPE(tracer_context_key, T_SYMBOL);
    // Note about rb_to_id and dynamic symbols: calling `rb_to_id` prevents symbols from ever being garbage collected.
    // In this case, we can't really escape this because as of this writing, ruby master still calls `rb_to_id` inside
    // the implementation of Thread#[]= so any symbol that gets used as a key there will already be prevented from GC.
    state->tracer_context_key = rb_to_id(tracer_context_key);
  }

  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(DDTRACE_UNUSED VALUE _self, VALUE collector_instance, VALUE profiler_overhead_stack_thread) {
  if (!is_thread_alive(profiler_overhead_stack_thread)) rb_raise(rb_eArgError, "Unexpected: profiler_overhead_stack_thread is not alive");

  cpu_and_wall_time_collector_sample(collector_instance, monotonic_wall_time_now_ns(RAISE_ON_FAILURE), profiler_overhead_stack_thread);
  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_on_gc_start(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  cpu_and_wall_time_collector_on_gc_start(collector_instance);
  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_on_gc_finish(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  cpu_and_wall_time_collector_on_gc_finish(collector_instance);
  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample_after_gc(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  cpu_and_wall_time_collector_sample_after_gc(collector_instance);
  return Qtrue;
}

// This function gets called from the Collectors::CpuAndWallTimeWorker to trigger the actual sampling.
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is allowed to raise exceptions. Caller is responsible for handling them, if needed.
// Assumption 3: This function IS NOT called from a signal handler. This function is not async-signal-safe.
// Assumption 4: This function IS NOT called in a reentrant way.
// Assumption 5: This function is called from the main Ractor (if Ruby has support for Ractors).
//
// The `profiler_overhead_stack_thread` is used to attribute the profiler overhead to a stack borrowed from a different thread
// (belonging to ddtrace), so that the overhead is visible in the profile rather than blamed on user code.
void cpu_and_wall_time_collector_sample(VALUE self_instance, long current_monotonic_wall_time_ns, VALUE profiler_overhead_stack_thread) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  VALUE current_thread = rb_thread_current();
  struct per_thread_context *current_thread_context = get_or_create_context_for(current_thread, state);
  long cpu_time_at_sample_start_for_current_thread = cpu_time_now_ns(current_thread_context);

  VALUE threads = thread_list(state);

  const long thread_count = RARRAY_LEN(threads);
  for (long i = 0; i < thread_count; i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    struct per_thread_context *thread_context = get_or_create_context_for(thread, state);

    // We account for cpu-time for the current thread in a different way -- we use the cpu-time at sampling start, to avoid
    // blaming the time the profiler took on whatever's running on the thread right now
    long current_cpu_time_ns = thread != current_thread ? cpu_time_now_ns(thread_context) : cpu_time_at_sample_start_for_current_thread;

    update_metrics_and_sample(
      state,
      /* thread_being_sampled: */ thread,
      /* stack_from_thread: */ thread,
      thread_context,
      current_cpu_time_ns,
      current_monotonic_wall_time_ns
    );
  }

  state->sample_count++;

  // TODO: This seems somewhat overkill and inefficient to do often; right now we just do it every few samples
  // but there's probably a better way to do this if we actually track when threads finish
  if (state->sample_count % 100 == 0) remove_context_for_dead_threads(state);

  update_metrics_and_sample(
    state,
    /* thread_being_sampled: */ current_thread,
    /* stack_from_thread: */ profiler_overhead_stack_thread,
    current_thread_context,
    cpu_time_now_ns(current_thread_context),
    monotonic_wall_time_now_ns(RAISE_ON_FAILURE)
  );
}

void update_metrics_and_sample(
  struct cpu_and_wall_time_collector_state *state,
  VALUE thread_being_sampled,
  VALUE stack_from_thread, // This can be different when attributing profiler overhead using a different stack
  struct per_thread_context *thread_context,
  long current_cpu_time_ns,
  long current_monotonic_wall_time_ns
) {
  long cpu_time_elapsed_ns = update_time_since_previous_sample(
    &thread_context->cpu_time_at_previous_sample_ns,
    current_cpu_time_ns,
    thread_context->gc_tracking.cpu_time_at_start_ns,
    IS_NOT_WALL_TIME
  );
  long wall_time_elapsed_ns = update_time_since_previous_sample(
    &thread_context->wall_time_at_previous_sample_ns,
    current_monotonic_wall_time_ns,
    thread_context->gc_tracking.wall_time_at_start_ns,
    IS_WALL_TIME
  );

  trigger_sample_for_thread(
    state,
    thread_being_sampled,
    stack_from_thread,
    thread_context,
    (sample_values) {.cpu_time_ns = cpu_time_elapsed_ns, .cpu_samples = 1, .wall_time_ns = wall_time_elapsed_ns},
    SAMPLE_REGULAR
  );
}

// This function gets called when Ruby is about to start running the Garbage Collector on the current thread.
// It updates the per_thread_context of the current thread to include the current cpu/wall times, to be used to later
// create a stack sample that blames the cpu/wall time spent from now until the end of the garbage collector work.
//
// Safety: This function gets called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is called from the main Ractor (if Ruby has support for Ractors).
void cpu_and_wall_time_collector_on_gc_start(VALUE self_instance) {
  struct cpu_and_wall_time_collector_state *state;
  if (!rb_typeddata_is_kind_of(self_instance, &cpu_and_wall_time_collector_typed_data)) return;
  // This should never fail the the above check passes
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  struct per_thread_context *thread_context = get_context_for(rb_thread_current(), state);

  // If there was no previously-existing context for this thread, we won't allocate one (see safety). For now we just drop
  // the GC sample, under the assumption that "a thread that is so new that we never sampled it even once before it triggers
  // GC" is a rare enough case that we can just ignore it.
  // We can always improve this later if we find that this happens often (and we have the counter to help us figure that out)!
  if (thread_context == NULL) {
    state->stats.gc_samples_missed_due_to_missing_context++;
    return;
  }

  // If these fields are set, there's an existing GC sample that still needs to be written out by `sample_after_gc`.
  //
  // When can this happen? Because we don't have precise control over when `sample_after_gc` gets called (it will be
  // called sometime after GC finishes), there is no way to guarantee that Ruby will not trigger more than one GC cycle
  // before we can actually run that method.
  //
  // We handle this by collapsing multiple GC cycles into one. That is, if the following happens:
  // `on_gc_start` (time=0) -> `on_gc_finish` (time=1) -> `on_gc_start` (time=2) -> `on_gc_finish` (time=3) -> `sample_after_gc`
  // then we just use time=0 from the first on_gc_start and time=3 from the last on_gc_finish, e.g. we behave as if
  // there was a single, longer GC period.
  if (thread_context->gc_tracking.cpu_time_at_finish_ns != INVALID_TIME &&
    thread_context->gc_tracking.wall_time_at_finish_ns != INVALID_TIME) return;

  // Here we record the wall-time first and in on_gc_finish we record it second to avoid having wall-time be slightly < cpu-time
  thread_context->gc_tracking.wall_time_at_start_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);
  thread_context->gc_tracking.cpu_time_at_start_ns = cpu_time_now_ns(thread_context);
}

// This function gets called when Ruby has finished running the Garbage Collector on the current thread.
// It updates the per_thread_context of the current thread to include the current cpu/wall times, to be used to later
// create a stack sample that blames the cpu/wall time spent from the start of garbage collector work until now.
//
// Safety: This function gets called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is called from the main Ractor (if Ruby has support for Ractors).
void cpu_and_wall_time_collector_on_gc_finish(VALUE self_instance) {
  struct cpu_and_wall_time_collector_state *state;
  if (!rb_typeddata_is_kind_of(self_instance, &cpu_and_wall_time_collector_typed_data)) return;
  // This should never fail the the above check passes
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  struct per_thread_context *thread_context = get_context_for(rb_thread_current(), state);

  // If there was no previously-existing context for this thread, we won't allocate one (see safety). We keep a metric for
  // how often this happens -- see on_gc_start.
  if (thread_context == NULL) return;

  if (thread_context->gc_tracking.cpu_time_at_start_ns == INVALID_TIME &&
    thread_context->gc_tracking.wall_time_at_start_ns == INVALID_TIME) {
    // If this happened, it means that on_gc_start was either never called for the thread OR it was called but no thread
    // context existed at the time. The former can be the result of a bug, but since we can't distinguish them, we just
    // do nothing.
    return;
  }

  // Here we record the wall-time second and in on_gc_start we record it first to avoid having wall-time be slightly < cpu-time
  thread_context->gc_tracking.cpu_time_at_finish_ns = cpu_time_now_ns(thread_context);
  thread_context->gc_tracking.wall_time_at_finish_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);
}

// This function gets called shortly after Ruby has finished running the Garbage Collector.
// It creates a new sample including the cpu and wall-time spent by the garbage collector work, and resets any
// GC-related tracking.
//
// Specifically, it will search for thread(s) which have gone through a cycle of on_gc_start/on_gc_finish
// and thus have cpu_time_at_start_ns, cpu_time_at_finish_ns, wall_time_at_start_ns, wall_time_at_finish_ns
// set on their context.
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is allowed to raise exceptions. Caller is responsible for handling them, if needed.
// Assumption 3: Unlike `on_gc_start` and `on_gc_finish`, this method is allowed to allocate memory as needed.
// Assumption 4: This function is called from the main Ractor (if Ruby has support for Ractors).
VALUE cpu_and_wall_time_collector_sample_after_gc(VALUE self_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  VALUE threads = thread_list(state);
  bool sampled_any_thread = false;

  const long thread_count = RARRAY_LEN(threads);
  for (long i = 0; i < thread_count; i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    struct per_thread_context *thread_context = get_or_create_context_for(thread, state);

    if (
      thread_context->gc_tracking.cpu_time_at_start_ns == INVALID_TIME ||
      thread_context->gc_tracking.cpu_time_at_finish_ns == INVALID_TIME ||
      thread_context->gc_tracking.wall_time_at_start_ns == INVALID_TIME ||
      thread_context->gc_tracking.wall_time_at_finish_ns == INVALID_TIME
    ) continue; // Ignore threads with no/incomplete garbage collection data

    sampled_any_thread = true;

    long gc_cpu_time_elapsed_ns =
      thread_context->gc_tracking.cpu_time_at_finish_ns - thread_context->gc_tracking.cpu_time_at_start_ns;
    long gc_wall_time_elapsed_ns =
      thread_context->gc_tracking.wall_time_at_finish_ns - thread_context->gc_tracking.wall_time_at_start_ns;

    // We don't expect non-wall time to go backwards, so let's flag this as a bug
    if (gc_cpu_time_elapsed_ns < 0) rb_raise(rb_eRuntimeError, "BUG: Unexpected negative gc_cpu_time_elapsed_ns between samples");
    // Wall-time can actually go backwards (e.g. when the system clock gets set) so we can't assume time going backwards
    // was a bug.
    // @ivoanjo: I've also observed time going backwards spuriously on macOS, see discussion on
    // https://github.com/DataDog/dd-trace-rb/pull/2336.
    if (gc_wall_time_elapsed_ns < 0) gc_wall_time_elapsed_ns = 0;

    if (thread_context->gc_tracking.wall_time_at_start_ns == 0 && thread_context->gc_tracking.wall_time_at_finish_ns != 0) {
      // Avoid using wall-clock if we got 0 for a start (meaning there was an error) but not 0 for finish so we don't
      // come up with a crazy value for the frame
      rb_raise(rb_eRuntimeError, "BUG: Unexpected zero value for gc_tracking.wall_time_at_start_ns");
    }

    trigger_sample_for_thread(
      state,
      /* thread: */  thread,
      /* stack_from_thread: */ thread,
      thread_context,
      (sample_values) {.cpu_time_ns = gc_cpu_time_elapsed_ns, .cpu_samples = 1, .wall_time_ns = gc_wall_time_elapsed_ns},
      SAMPLE_IN_GC
    );

    // Mark thread as no longer in GC
    thread_context->gc_tracking.cpu_time_at_start_ns = INVALID_TIME;
    thread_context->gc_tracking.cpu_time_at_finish_ns = INVALID_TIME;
    thread_context->gc_tracking.wall_time_at_start_ns = INVALID_TIME;
    thread_context->gc_tracking.wall_time_at_finish_ns = INVALID_TIME;

    // Update counters so that they won't include the time in GC during the next sample
    if (thread_context->cpu_time_at_previous_sample_ns != INVALID_TIME) {
      thread_context->cpu_time_at_previous_sample_ns += gc_cpu_time_elapsed_ns;
    }
    if (thread_context->wall_time_at_previous_sample_ns != INVALID_TIME) {
      thread_context->wall_time_at_previous_sample_ns += gc_wall_time_elapsed_ns;
    }
  }

  if (sampled_any_thread) state->stats.gc_samples++;

  // Return a VALUE to make it easier to call this function from Ruby APIs that expect a return value (such as rb_rescue2)
  return Qnil;
}

static void trigger_sample_for_thread(
  struct cpu_and_wall_time_collector_state *state,
  VALUE thread,
  VALUE stack_from_thread, // This can be different when attributing profiler overhead using a different stack
  struct per_thread_context *thread_context,
  sample_values values,
  sample_type type
) {
  int max_label_count =
    1 + // thread id
    1 + // thread name
    1 + // profiler overhead
    2;  // local root span id and span id
  ddog_prof_Label labels[max_label_count];
  int label_pos = 0;

  labels[label_pos++] = (ddog_prof_Label) {
    .key = DDOG_CHARSLICE_C("thread id"),
    .str = thread_context->thread_id_char_slice
  };

  VALUE thread_name = thread_name_for(thread);
  if (thread_name != Qnil) {
    labels[label_pos++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("thread name"),
      .str = char_slice_from_ruby_string(thread_name)
    };
  }

  struct trace_identifiers trace_identifiers_result = {.valid = false, .trace_endpoint = Qnil};
  trace_identifiers_for(state, thread, &trace_identifiers_result);

  if (trace_identifiers_result.valid) {
    labels[label_pos++] = (ddog_prof_Label) {.key = DDOG_CHARSLICE_C("local root span id"), .num = trace_identifiers_result.local_root_span_id};
    labels[label_pos++] = (ddog_prof_Label) {.key = DDOG_CHARSLICE_C("span id"), .num = trace_identifiers_result.span_id};

    if (trace_identifiers_result.trace_endpoint != Qnil) {
      // The endpoint gets recorded in a different way because it is mutable in the tracer and can change during a
      // trace.
      //
      // Instead of each sample for the same local_root_span_id getting a potentially-different endpoint,
      // `record_endpoint` (via libdatadog) keeps a list of local_root_span_id values and their most-recently-seen
      // endpoint values, and at serialization time the most-recently-seen endpoint is applied to all relevant samples.
      //
      // This is why the endpoint is not directly added in this function to the labels array, although it will later
      // show up in the array in the output pprof.
      record_endpoint(
        state->recorder_instance,
        trace_identifiers_result.local_root_span_id,
        char_slice_from_ruby_string(trace_identifiers_result.trace_endpoint)
      );
    }
  }

  if (thread != stack_from_thread) {
    labels[label_pos++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("profiler overhead"),
      .num = 1
    };
  }

  // The number of times `label_pos++` shows up in this function needs to match `max_label_count`. To avoid "oops I
  // forgot to update max_label_count" in the future, we've also added this validation.
  // @ivoanjo: I wonder if C compilers are smart enough to statically prove when this check never triggers happens and
  // remove it entirely.
  if (label_pos > max_label_count) {
    rb_raise(rb_eRuntimeError, "BUG: Unexpected label_pos (%d) > max_label_count (%d)", label_pos, max_label_count);
  }

  sample_thread(
    stack_from_thread,
    state->sampling_buffer,
    state->recorder_instance,
    values,
    (ddog_prof_Slice_Label) {.ptr = labels, .len = label_pos},
    type
  );
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_thread_list(DDTRACE_UNUSED VALUE _self) {
  VALUE result = rb_ary_new();
  ddtrace_thread_list(result);
  return result;
}

static struct per_thread_context *get_or_create_context_for(VALUE thread, struct cpu_and_wall_time_collector_state *state) {
  struct per_thread_context* thread_context = NULL;
  st_data_t value_context = 0;

  if (st_lookup(state->hash_map_per_thread_context, (st_data_t) thread, &value_context)) {
    thread_context = (struct per_thread_context*) value_context;
  } else {
    thread_context = ruby_xcalloc(1, sizeof(struct per_thread_context));
    initialize_context(thread, thread_context);
    st_insert(state->hash_map_per_thread_context, (st_data_t) thread, (st_data_t) thread_context);
  }

  return thread_context;
}

static struct per_thread_context *get_context_for(VALUE thread, struct cpu_and_wall_time_collector_state *state) {
  struct per_thread_context* thread_context = NULL;
  st_data_t value_context = 0;

  if (st_lookup(state->hash_map_per_thread_context, (st_data_t) thread, &value_context)) {
    thread_context = (struct per_thread_context*) value_context;
  }

  return thread_context;
}

static void initialize_context(VALUE thread, struct per_thread_context *thread_context) {
  snprintf(thread_context->thread_id, THREAD_ID_LIMIT_CHARS, "%"PRIu64" (%lu)", native_thread_id_for(thread), (unsigned long) thread_id_for(thread));
  thread_context->thread_id_char_slice = (ddog_CharSlice) {.ptr = thread_context->thread_id, .len = strlen(thread_context->thread_id)};

  thread_context->thread_cpu_time_id = thread_cpu_time_id_for(thread);

  // These will get initialized during actual sampling
  thread_context->cpu_time_at_previous_sample_ns = INVALID_TIME;
  thread_context->wall_time_at_previous_sample_ns = INVALID_TIME;

  // These will only be used during a GC operation
  thread_context->gc_tracking.cpu_time_at_start_ns = INVALID_TIME;
  thread_context->gc_tracking.cpu_time_at_finish_ns = INVALID_TIME;
  thread_context->gc_tracking.wall_time_at_start_ns = INVALID_TIME;
  thread_context->gc_tracking.wall_time_at_finish_ns = INVALID_TIME;
}

static VALUE _native_inspect(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  VALUE result = rb_str_new2(" (native state)");

  // Update this when modifying state struct
  rb_str_concat(result, rb_sprintf(" hash_map_per_thread_context=%"PRIsVALUE, per_thread_context_st_table_as_ruby_hash(state)));
  rb_str_concat(result, rb_sprintf(" recorder_instance=%"PRIsVALUE, state->recorder_instance));
  VALUE tracer_context_key = state->tracer_context_key == MISSING_TRACER_CONTEXT_KEY ? Qnil : ID2SYM(state->tracer_context_key);
  rb_str_concat(result, rb_sprintf(" tracer_context_key=%+"PRIsVALUE, tracer_context_key));
  rb_str_concat(result, rb_sprintf(" sample_count=%u", state->sample_count));
  rb_str_concat(result, rb_sprintf(" stats=%"PRIsVALUE, stats_as_ruby_hash(state)));

  return result;
}

static VALUE per_thread_context_st_table_as_ruby_hash(struct cpu_and_wall_time_collector_state *state) {
  VALUE result = rb_hash_new();
  st_foreach(state->hash_map_per_thread_context, per_thread_context_as_ruby_hash, result);
  return result;
}

static int per_thread_context_as_ruby_hash(st_data_t key_thread, st_data_t value_context, st_data_t result_hash) {
  VALUE thread = (VALUE) key_thread;
  struct per_thread_context *thread_context = (struct per_thread_context*) value_context;
  VALUE result = (VALUE) result_hash;
  VALUE context_as_hash = rb_hash_new();
  rb_hash_aset(result, thread, context_as_hash);

  VALUE arguments[] = {
    ID2SYM(rb_intern("thread_id")),                       /* => */ rb_str_new2(thread_context->thread_id),
    ID2SYM(rb_intern("thread_cpu_time_id_valid?")),       /* => */ thread_context->thread_cpu_time_id.valid ? Qtrue : Qfalse,
    ID2SYM(rb_intern("thread_cpu_time_id")),              /* => */ CLOCKID2NUM(thread_context->thread_cpu_time_id.clock_id),
    ID2SYM(rb_intern("cpu_time_at_previous_sample_ns")),  /* => */ LONG2NUM(thread_context->cpu_time_at_previous_sample_ns),
    ID2SYM(rb_intern("wall_time_at_previous_sample_ns")), /* => */ LONG2NUM(thread_context->wall_time_at_previous_sample_ns),

    ID2SYM(rb_intern("gc_tracking.cpu_time_at_start_ns")),   /* => */ LONG2NUM(thread_context->gc_tracking.cpu_time_at_start_ns),
    ID2SYM(rb_intern("gc_tracking.cpu_time_at_finish_ns")),  /* => */ LONG2NUM(thread_context->gc_tracking.cpu_time_at_finish_ns),
    ID2SYM(rb_intern("gc_tracking.wall_time_at_start_ns")),  /* => */ LONG2NUM(thread_context->gc_tracking.wall_time_at_start_ns),
    ID2SYM(rb_intern("gc_tracking.wall_time_at_finish_ns")), /* => */ LONG2NUM(thread_context->gc_tracking.wall_time_at_finish_ns)
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(context_as_hash, arguments[i], arguments[i+1]);

  return ST_CONTINUE;
}

static VALUE stats_as_ruby_hash(struct cpu_and_wall_time_collector_state *state) {
  // Update this when modifying state struct (stats inner struct)
  VALUE stats_as_hash = rb_hash_new();
  VALUE arguments[] = {
    ID2SYM(rb_intern("gc_samples")),                               /* => */ UINT2NUM(state->stats.gc_samples),
    ID2SYM(rb_intern("gc_samples_missed_due_to_missing_context")), /* => */ UINT2NUM(state->stats.gc_samples_missed_due_to_missing_context),
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(stats_as_hash, arguments[i], arguments[i+1]);
  return stats_as_hash;
}

static void remove_context_for_dead_threads(struct cpu_and_wall_time_collector_state *state) {
  st_foreach(state->hash_map_per_thread_context, remove_if_dead_thread, 0 /* unused */);
}

static int remove_if_dead_thread(st_data_t key_thread, st_data_t value_context, DDTRACE_UNUSED st_data_t _argument) {
  VALUE thread = (VALUE) key_thread;
  struct per_thread_context* thread_context = (struct per_thread_context*) value_context;

  if (is_thread_alive(thread)) return ST_CONTINUE;

  ruby_xfree(thread_context);
  return ST_DELETE;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
//
// Returns the whole contents of the per_thread_context structs being tracked.
static VALUE _native_per_thread_context(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  return per_thread_context_st_table_as_ruby_hash(state);
}

static long update_time_since_previous_sample(long *time_at_previous_sample_ns, long current_time_ns, long gc_start_time_ns, bool is_wall_time) {
  // If we didn't have a time for the previous sample, we use the current one
  if (*time_at_previous_sample_ns == INVALID_TIME) *time_at_previous_sample_ns = current_time_ns;

  bool is_thread_doing_gc = gc_start_time_ns != INVALID_TIME;
  long elapsed_time_ns = -1;

  if (is_thread_doing_gc) {
    bool previous_sample_was_during_gc = gc_start_time_ns <= *time_at_previous_sample_ns;

    if (previous_sample_was_during_gc) {
      elapsed_time_ns = 0; // No time to account for -- any time since the last sample is going to get assigned to GC separately
    } else {
      elapsed_time_ns = gc_start_time_ns - *time_at_previous_sample_ns; // Capture time between previous sample and start of GC only
    }

    // Remaining time (from gc_start_time to current_time_ns) will be accounted for inside `sample_after_gc`
    *time_at_previous_sample_ns = gc_start_time_ns;
  } else {
    elapsed_time_ns = current_time_ns - *time_at_previous_sample_ns; // Capture all time since previous sample
    *time_at_previous_sample_ns = current_time_ns;
  }

  if (elapsed_time_ns < 0) {
    if (is_wall_time) {
      // Wall-time can actually go backwards (e.g. when the system clock gets set) so we can't assume time going backwards
      // was a bug.
      // @ivoanjo: I've also observed time going backwards spuriously on macOS, see discussion on
      // https://github.com/DataDog/dd-trace-rb/pull/2336.
      elapsed_time_ns = 0;
    } else {
      // We don't expect non-wall time to go backwards, so let's flag this as a bug
      rb_raise(rb_eRuntimeError, "BUG: Unexpected negative elapsed_time_ns between samples");
    }
  }

  return elapsed_time_ns;
}

// Safety: This function is assumed never to raise exceptions by callers
static long cpu_time_now_ns(struct per_thread_context *thread_context) {
  thread_cpu_time cpu_time = thread_cpu_time_for(thread_context->thread_cpu_time_id);

  if (!cpu_time.valid) {
    // Invalidate previous state of the counter (if any), it's no longer accurate. We need to get two good reads
    // in a row to have an accurate delta.
    thread_context->cpu_time_at_previous_sample_ns = INVALID_TIME;
    return 0;
  }

  return cpu_time.result_ns;
}

static long thread_id_for(VALUE thread) {
  VALUE object_id = rb_obj_id(thread);

  // The API docs for Ruby state that `rb_obj_id` COULD be a BIGNUM and that if you want to be really sure you don't
  // get a BIGNUM, then you should use `rb_memory_id`. But `rb_memory_id` is less interesting because it's less visible
  // at the user level than the result of calling `#object_id`.
  //
  // It also seems uncommon to me that we'd ever get a BIGNUM; on old Ruby versions (pre-GC compaction), the object id
  // was the pointer to the object, so that's not going to be a BIGNUM; on modern Ruby versions, Ruby keeps
  // a counter, and only increments it for objects for which `#object_id`/`rb_obj_id` is called (e.g. most objects
  // won't actually have an object id allocated).
  //
  // So, for now, let's simplify: we only support FIXNUMs, and we won't break if we get a BIGNUM; we just won't
  // record the thread_id (but samples will still be collected).
  return FIXNUM_P(object_id) ? FIX2LONG(object_id) : -1;
}

VALUE enforce_cpu_and_wall_time_collector_instance(VALUE object) {
  Check_TypedStruct(object, &cpu_and_wall_time_collector_typed_data);
  return object;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
//
// Returns the whole contents of the per_thread_context structs being tracked.
static VALUE _native_stats(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  return stats_as_ruby_hash(state);
}

// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
static void trace_identifiers_for(struct cpu_and_wall_time_collector_state *state, VALUE thread, struct trace_identifiers *trace_identifiers_result) {
  if (state->tracer_context_key == MISSING_TRACER_CONTEXT_KEY) return;

  VALUE current_context = rb_thread_local_aref(thread, state->tracer_context_key);
  if (current_context == Qnil) return;

  VALUE active_trace = rb_ivar_get(current_context, at_active_trace_id /* @active_trace */);
  if (active_trace == Qnil) return;

  VALUE root_span = rb_ivar_get(active_trace, at_root_span_id /* @root_span */);
  VALUE active_span = rb_ivar_get(active_trace, at_active_span_id /* @active_span */);
  if (root_span == Qnil || active_span == Qnil) return;

  VALUE numeric_local_root_span_id = rb_ivar_get(root_span, at_id_id /* @id */);
  VALUE numeric_span_id = rb_ivar_get(active_span, at_id_id /* @id */);
  if (numeric_local_root_span_id == Qnil || numeric_span_id == Qnil) return;

  trace_identifiers_result->local_root_span_id = NUM2ULL(numeric_local_root_span_id);
  trace_identifiers_result->span_id = NUM2ULL(numeric_span_id);

  trace_identifiers_result->valid = true;

  VALUE root_span_type = rb_ivar_get(root_span, at_type_id /* @type */);
  if (root_span_type == Qnil || !is_type_web(root_span_type)) return;

  VALUE trace_resource = rb_ivar_get(active_trace, at_resource_id /* @resource */);
  if (RB_TYPE_P(trace_resource, T_STRING)) {
    trace_identifiers_result->trace_endpoint = trace_resource;
  } else if (trace_resource == Qnil) {
    // Fall back to resource from span, if any
    trace_identifiers_result->trace_endpoint = rb_ivar_get(root_span, at_resource_id /* @resource */);
  }
}

static bool is_type_web(VALUE root_span_type) {
  ENFORCE_TYPE(root_span_type, T_STRING);

  return RSTRING_LEN(root_span_type) == strlen("web") &&
    (memcmp("web", StringValuePtr(root_span_type), strlen("web")) == 0);
}

// After the Ruby VM forks, this method gets called in the child process to clean up any leftover state from the parent.
//
// Assumption: This method gets called BEFORE restarting profiling -- e.g. there are no components attempting to
// trigger samples at the same time.
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  st_clear(state->hash_map_per_thread_context);

  state->stats = (struct stats) {}; // Resets all stats back to zero

  rb_funcall(state->recorder_instance, rb_intern("reset_after_fork"), 0);

  return Qtrue;
}

static VALUE thread_list(struct cpu_and_wall_time_collector_state *state) {
  VALUE result = state->thread_list_buffer;
  rb_ary_clear(result);
  ddtrace_thread_list(result);
  return result;
}
