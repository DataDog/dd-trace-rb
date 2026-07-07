#include <ruby.h>
#include <ruby/debug.h>

#include "datadog_ruby_common.h"
#include "collectors_thread_context.h"
#include "clock_id.h"
#include "collectors_stack.h"
#include "collectors_gc_profiling_helper.h"
#include "helpers.h"
#include "libdatadog_helpers.h"
#include "private_vm_api_access.h"
#include "ruby_helpers.h"
#include "stack_recorder.h"
#include "time_helpers.h"
#include "unsafe_api_calls_check.h"
#include "extconf.h"

// Used to trigger sampling of threads, based on external "events", such as:
// * periodic timer for cpu-time and wall-time
// * VM garbage collection events
// * VM object allocation events
//
// This file implements the native bits of the Datadog::Profiling::Collectors::ThreadContext class
//
// Triggering of this component (e.g. watching for the above "events") is implemented by Collectors::CpuAndWallTimeWorker.

// ---
// ## Tracking of cpu-time and wall-time spent during garbage collection
//
// This feature works by having a special state that a thread can be in: doing garbage collection. This state is
// tracked inside the thread's `per_thread_context.gc_tracking` data, and three functions, listed below. The functions
// will get called by the `Collectors::CpuAndWallTimeWorker` at very specific times in the VM lifetime.
//
// * `thread_context_collector_on_gc_start`: Called at the very beginning of the garbage collection process.
//   The internal VM `during_gc` flag is set to `true`, but Ruby has not done any work yet.
// * `thread_context_collector_on_gc_finish`: Called at the very end of the garbage collection process.
//   The internal VM `during_gc` flag is still set to `true`, but all the work has been done.
// * `thread_context_collector_sample_after_gc`: Called shortly after the garbage collection process.
//   The internal VM `during_gc` flag is set to `false`.
//
// Inside this component, here's what happens inside those three functions:
//
// When `thread_context_collector_on_gc_start` gets called, the current cpu and wall-time get recorded to the thread
// context: `cpu_time_at_gc_start_ns` and `wall_time_at_gc_start_ns`.
//
// While `cpu_time_at_gc_start_ns` is set, regular samples (if any) do not account for cpu-time any time that passes
// after this timestamp. The idea is that this cpu-time will be blamed separately on GC, and not on the user thread.
// Wall-time accounting is not affected by this (e.g. we still record 60 seconds every 60 seconds).
//
// (Regular samples can still account for the cpu-time between the previous sample and the start of GC.)
//
// When `thread_context_collector_on_gc_finish` gets called, the cpu-time and wall-time spent during GC gets recorded
// into the global gc_tracking structure, and further samples are not affected. (The `cpu_time_at_previous_sample_ns`
// of the thread that did GC also gets adjusted to avoid double-accounting.)
//
// Finally, when `thread_context_collector_sample_after_gc` gets called, a sample gets recorded with a stack having
// a single placeholder `Garbage Collection` frame. This sample gets
// assigned the cpu-time and wall-time that was recorded between calls to `on_gc_start` and `on_gc_finish`, as well
// as metadata for the last GC.
//
// Note that the Ruby GC does not usually do all of the GC work in one go. Instead, it breaks it up into smaller steps
// so that the application can keep doing user work in between GC steps.
// The `on_gc_start` / `on_gc_finish` will trigger each time the VM executes these smaller steps, and on a benchmark
// that executes `Object.new` in a loop, I measured more than 50k of this steps per second (!!).
// Creating these many events for every GC step is a lot of overhead, so instead `on_gc_finish` coalesces time
// spent in GC and only flushes it at most every 10 ms/every complete GC collection. This reduces the amount of
// individual GC events we need to record. We use the latest GC metadata for this event, reflecting the last GC that
// happened in the coalesced period.
//
// In an earlier attempt at implementing this functionality (https://github.com/DataDog/dd-trace-rb/pull/2308), we
// discovered that we needed to factor the sampling work away from `thread_context_collector_on_gc_finish` and into a
// separate `thread_context_collector_sample_after_gc` because (as documented in more detail below),
// `sample_after_gc` could trigger memory allocation in rare occasions (usually exceptions), which is actually not
// allowed to happen during Ruby's garbage collection start/finish hooks.
// ---

#define THREAD_ID_LIMIT_CHARS 44 // Why 44? "#{2**64} (#{2**64})".size + 1 for \0
#define THREAD_INVOKE_LOCATION_LIMIT_CHARS 512
#define IS_WALL_TIME true
#define IS_CPU_TIME false
#define MISSING_TRACER_CONTEXT_KEY 0
#define TIME_BETWEEN_GC_EVENTS_NS MILLIS_AS_NS(10)
#define GVL_SUSPENDED ((uint64_t)1)
#define GVL_RUNNING ((uint64_t)0)

#define MAX(a, b) ((a) < (b) ? (b) : (a))

static ID dd_per_thread_context_id; // Hidden ivar (no @ prefix, inaccessible from Ruby)

static ID at_active_span_id;  // id of :@active_span in Ruby
static ID at_active_trace_id; // id of :@active_trace in Ruby
static ID at_id_id;           // id of :@id in Ruby
static ID at_resource_id;     // id of :@resource in Ruby
static ID at_root_span_id;    // id of :@root_span in Ruby
static ID at_type_id;         // id of :@type in Ruby
static ID at_otel_values_id;  // id of :@otel_values in Ruby
static ID at_parent_span_id_id; // id of :@parent_span_id in Ruby
static ID at_datadog_trace_id;  // id of :@datadog_trace in Ruby

// Used to support reading trace identifiers from the opentelemetry Ruby library when the ddtrace gem tracing
// integration is NOT in use.
static ID at_span_id_id;  // id of :@span_id in Ruby
static ID at_trace_id_id; // id of :@trace_id in Ruby
static ID at_entries_id;  // id of :@entries in Ruby
static ID at_context_id;  // id of :@context in Ruby
static ID at_kind_id;     // id of :@kind in Ruby
static ID at_name_id;     // id of :@name in Ruby
static ID server_id;      // id of :server in Ruby
static ID otel_context_storage_id; // id of :__opentelemetry_context_storage__ in Ruby
static ID otel_fiber_context_storage_id; // id of :@opentelemetry_context in Ruby

// This is mutable and gets set last-writer-wins style by
// `thread_context_collector_reset_all_per_thread_contexts`, which is called whenever
// profiling is starting or restating.
//
// Note: We must be careful to not change this value while the profiler is still running,
// otherwise new threads can get the new value and cause profiling to stop with an
// exception due to the mismatched size.
//
// The initial value should be kept in sync with the default for DD_PROFILING_MAX_FRAMES
// in settings.rb. See `initialize_context` for details on why this is needed/used.
static uint16_t latest_max_frames = 400;

// Global tracepoint for RUBY_EVENT_THREAD_BEGIN. Created and enabled once when the first ThreadContext collector is initialized.
static VALUE thread_begin_tracepoint = Qnil;

typedef enum { OTEL_CONTEXT_ENABLED_FALSE, OTEL_CONTEXT_ENABLED_ONLY, OTEL_CONTEXT_ENABLED_BOTH } otel_context_enabled;
typedef enum { OTEL_CONTEXT_SOURCE_UNKNOWN, OTEL_CONTEXT_SOURCE_FIBER_IVAR, OTEL_CONTEXT_SOURCE_FIBER_LOCAL } otel_context_source;

// Contains state for a single ThreadContext instance
typedef struct {
  // Note: Places in this file that usually need to be changed when this struct is changed are tagged with
  // "Update this when modifying state struct"

  // Output buffer for stack traces, passed to sample_thread()
  sample_locations locations;
  // Datadog::Profiling::StackRecorder instance
  VALUE recorder_instance;
  // If the tracer is available and enabled, this will be the fiber-local symbol for accessing its running context,
  // to enable code hotspots and endpoint aggregation.
  // When not available, this is set to MISSING_TRACER_CONTEXT_KEY.
  ID tracer_context_key;
  // Reusable array to get list of threads
  VALUE thread_list_buffer;
  // Used to omit endpoint names (retrieved from tracer) from collected data
  bool endpoint_collection_enabled;
  // Used to control context collection
  otel_context_enabled otel_context_enabled;
  // Used to remember where otel context is being stored after we observe it the first time
  otel_context_source otel_context_source;
  // Used when calling monotonic_to_system_epoch_ns
  monotonic_to_system_epoch_state time_converter_state;
  // Used to identify the main thread, to give it a fallback name
  VALUE main_thread;
  // Used when extracting trace identifiers from otel spans. Lazily initialized.
  // Qtrue serves as a marker we've not yet extracted it; when we try to extract it, we set it to an object if
  // successful and Qnil if not.
  VALUE otel_current_span_key;
  // Used to enable native filenames in stack traces
  bool native_filenames_enabled;
  // Used to cache native filename lookup results (Map[void *function_pointer, char *filename])
  st_table *native_filenames_cache;
  // Used to attribute overhead during sampling to this component
  VALUE overhead_filename;
  // Minimum duration of a "Waiting for GVL" period to trigger a sample
  uint32_t waiting_for_gvl_threshold_ns;

  struct stats {
    // Track how many regular samples we've taken. Does not include garbage collection samples.
    unsigned int sample_count;
    // Track how many garbage collection samples we've taken.
    unsigned int gc_samples;
    // See thread_context_collector_on_gc_start for details
    unsigned int gc_samples_missed_due_to_missing_context;
    // How many per-thread samples were skipped because the thread has been continuously suspended
    // (no GVL) since its previous sample, so its Ruby stack cannot have changed.
    unsigned int inactive_thread_samples_skipped;
    unsigned int profiler_thread_samples_skipped;
  } stats;

  struct {
    unsigned long accumulated_cpu_time_ns;
    unsigned long accumulated_wall_time_ns;

    long wall_time_at_previous_gc_ns; // Will be INVALID_TIME unless there's accumulated time above
    long wall_time_at_last_flushed_gc_event_ns; // Starts at 0 and then will always be valid
  } gc_tracking;
} thread_context_collector_state;

// Tracks per-thread state.
// This state is global and lives forever on the Ruby Thread (until the Thread is GC'd).
// The state is created early on for all threads on the main Ractor
// (enabling a TracePoint only enables it for the current Ractor).
// The state is either created when the Thread starts running (via the RUBY_EVENT_THREAD_BEGIN TracePoint),
// or via `thread_context_collector_reset_all_per_thread_contexts` when the profiler starts.
//
// Unfortunately that RUBY_EVENT_THREAD_BEGIN TracePoint still fires after some other events:
// * RUBY_INTERNAL_THREAD_EVENT_RESUMED for the Thread acquiring the GVL for the first time
// * an early SIGPROF calling handle_sampling_signal()
// * Ruby might check for interrupts and run postponed jobs (e.g. thread_context_collector_sample)
// * another RUBY_EVENT_THREAD_BEGIN TracePoint which might run before ours
// * etc
// For those cases we have to ignore those events and we cannot assume the state is always set,
// however this only matters for a very short period when a thread starts.
struct per_thread_context {
  sampling_buffer sampling_buffer;
  char thread_id[THREAD_ID_LIMIT_CHARS];
  ddog_CharSlice thread_id_char_slice;
  char thread_invoke_location[THREAD_INVOKE_LOCATION_LIMIT_CHARS];
  ddog_CharSlice thread_invoke_location_char_slice;
  thread_cpu_time_id thread_cpu_time_id;
  long cpu_time_at_previous_sample_ns;
  long wall_time_at_previous_sample_ns;

  // There are 3 possible states for the GVL (per thread), and 3 transitions for which we receive GVL events:
  // Thread holds the GVL
  //   on_gvl_released() the thread releases the GVL (RUBY_INTERNAL_THREAD_EVENT_SUSPENDED)
  // Thread runs without the GVL
  //   on_gvl_waiting() the thread wants the GVL (RUBY_INTERNAL_THREAD_EVENT_READY)
  // Thread is "Waiting for GVL"
  //   on_gvl_running() the thread now got the GVL (RUBY_INTERNAL_THREAD_EVENT_RESUMED)
  // ... and the cycle restarts


  // --- GVL waiting tracking state machine ---
  //
  // gvl_waiting_at tracks the GVL wait state for each profiled thread:
  //
  //        ┌───────────────────────────────────┐
  //        │           on_gvl_waiting          │
  //        │                                   ▼
  //   Not Waiting (0) ◀────────────────── Waiting (> 0)
  //        ▲            on_gvl_running         │
  //        │          (below threshold)        │ on_gvl_running (above threshold)
  //        │                                   ▼
  //        └─────────────────────────── Sample Pending (< 0)
  //      sample / sample_after_gvl_running
  //
  // Not Waiting (0):      thread is running or not waiting for the GVL
  // Waiting (> 0):        monotonic wall time (ns) when the thread started waiting
  // Sample Pending (< 0): negated timestamp; the wait ended and a sample is pending
  //
  // The field is accessed under the GVL for most functions EXCEPT on_gvl_waiting() which writes to it without the GVL.
  // So we need to pack the above state in a single long to ensure atomicity.
  long gvl_waiting_at;

  // Per-thread "state + version" word, updated on every GVL state transition. The encoding is:
  //   - low bit:  current state (1 = currently suspended, 0 = currently running)
  //   - bits 1+:  monotonic event counter (incremented on every RESUMED)
  // The hooks set the state bit explicitly rather than relying on parity, so the encoding stays
  // correct even when events are not paired properly (as in tests).
  //
  // Note that SUSPENDED can happen multiple times in a row on Ruby 3.2,
  // see https://github.com/DataDog/dd-trace-rb/pull/5777#discussion_r3388560254,
  // the encoding is designed to naturally not change the field in such a case.
  uint64_t gvl_state_change_count;
  // Snapshot of the thread's gvl_state_change_count at the moment we last sampled it.
  // Equality with this snapshot means no GVL transition since the last sample.
  uint64_t gvl_state_change_count_at_previous_sample;
  // True when the previous per-tick sample was skipped by the SUSPENDED-skip optimization, so the
  // flush-before-serialize pass knows it needs to report this thread.
  // As a result, we will accumulate all wall & CPU time as a single batch per reporting period,
  // but this is deemed worth it for this optimization. In any case we don't know exactly
  // at what time a thread was doing CPU work (unless it's on CPU 100% of the time).
  bool was_skipped_at_last_sample;
  // Set as true for CpuAndWallTimeWorker and IdleSamplingHelper threads.
  // When true, per-tick samples are skipped entirely; the thread is sampled only once per
  // reporting period during the on_serialize flush.
  //
  // These threads are always in native code so their stacks aren't interesting;
  // the Profiling::Scheduler thread on the other hand does a lot of different
  // things using a mix of Ruby and native code, so that one isn't considered internal.
  bool is_profiler_internal_thread;

  struct {
    // Both of these fields are set by on_gc_start and kept until on_gc_finish is called.
    // Outside of this window, they will be INVALID_TIME.
    long cpu_time_at_start_ns;
    long wall_time_at_start_ns;
  } gc_tracking;
};

// Used to correlate profiles with traces
typedef struct {
  bool valid;
  uint64_t local_root_span_id;
  uint64_t span_id;
  VALUE trace_endpoint;
} trace_identifiers;

typedef struct {
  VALUE span;
  VALUE span_id;
  VALUE trace_id;
} otel_span;

static void thread_context_collector_typed_data_mark(void *state_ptr);
static void thread_context_collector_typed_data_free(void *state_ptr);
static void per_thread_context_typed_data_mark(void *ctx_ptr);
static void per_thread_context_typed_data_free(void *ctx_ptr);
static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_sample(VALUE self, VALUE collector_instance, VALUE allow_exception);
static VALUE _native_on_gc_start(VALUE self, VALUE collector_instance);
static VALUE _native_on_gc_finish(VALUE self, VALUE collector_instance);
static VALUE _native_sample_after_gc(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE allow_exception);
static void update_metrics_and_sample(
  thread_context_collector_state *state,
  VALUE thread_being_sampled,
  per_thread_context *thread_context,
  long current_cpu_time_ns,
  long current_monotonic_wall_time_ns,
  bool force_sample
);
static void trigger_sample_for_thread(
  thread_context_collector_state *state,
  VALUE thread_being_sampled,
  per_thread_context *thread_context,
  sample_values values,
  long current_monotonic_wall_time_ns,
  ddog_CharSlice *ruby_vm_type,
  ddog_CharSlice *class_name,
  bool is_gvl_waiting_state,
  bool is_safe_to_allocate_objects
);
static VALUE _native_thread_list(VALUE self);
static void check_frozen_thread(VALUE thread);
static per_thread_context *get_or_create_context_for(VALUE thread);
static void initialize_context(VALUE thread, per_thread_context *thread_context);
static VALUE _native_inspect(VALUE self, VALUE collector_instance);
static VALUE per_thread_context_to_ruby_hash(per_thread_context *thread_context);
static VALUE stats_to_ruby_hash(thread_context_collector_state *state, VALUE hash);
static VALUE gc_tracking_as_ruby_hash(thread_context_collector_state *state);
static VALUE _native_per_thread_context(VALUE self, VALUE collector_instance);
static long update_time_since_previous_sample(long *time_at_previous_sample_ns, long current_time_ns, long gc_start_time_ns, bool is_wall_time);
static long cpu_time_now_ns(per_thread_context *thread_context);
static long thread_id_for(VALUE thread);
static VALUE _native_stats(VALUE self, VALUE collector_instance);
static VALUE _native_gc_tracking(VALUE self, VALUE collector_instance);
static void trace_identifiers_for(
  thread_context_collector_state *state,
  VALUE thread,
  trace_identifiers *trace_identifiers_result,
  bool is_safe_to_allocate_objects
);
static bool should_collect_resource(VALUE root_span);
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE collector_instance);
static VALUE thread_list(thread_context_collector_state *state);
static VALUE _native_sample_allocation(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE sample_weight, VALUE new_object);
static VALUE _native_new_empty_thread(VALUE self);
static ddog_CharSlice ruby_value_type_to_class_name(enum ruby_value_type type);
static void ddtrace_otel_trace_identifiers_for(
  thread_context_collector_state *state,
  VALUE *active_trace,
  VALUE *root_span,
  VALUE *numeric_span_id,
  VALUE active_span,
  VALUE otel_values,
  bool is_safe_to_allocate_objects
);
static VALUE _native_sample_skipped_allocation_samples(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE skipped_samples);
static bool handle_gvl_waiting(
  thread_context_collector_state *state,
  VALUE thread_being_sampled,
  per_thread_context *thread_context,
  long current_cpu_time_ns
);
#ifndef NO_GVL_INSTRUMENTATION
  static VALUE _native_on_gvl_waiting(DDTRACE_UNUSED VALUE self, VALUE thread);
  static VALUE _native_gvl_waiting_at_for(DDTRACE_UNUSED VALUE self, VALUE thread);
  static VALUE _native_on_gvl_running(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE thread);
  static VALUE _native_on_gvl_released(DDTRACE_UNUSED VALUE self, VALUE thread);
  static VALUE _native_sample_after_gvl_running(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE thread, VALUE allow_exception);
#endif
static VALUE _native_apply_delta_to_cpu_time_at_previous_sample_ns(DDTRACE_UNUSED VALUE self, VALUE thread, VALUE delta_ns);
static void otel_without_ddtrace_trace_identifiers_for(
  thread_context_collector_state *state,
  VALUE thread,
  trace_identifiers *trace_identifiers_result,
  bool is_safe_to_allocate_objects
);
static otel_span otel_span_from(VALUE otel_context, VALUE otel_current_span_key);
static uint64_t otel_span_id_to_uint(VALUE otel_span_id);
static VALUE safely_lookup_hash_without_going_into_ruby_code(VALUE hash, VALUE key);
static VALUE _native_system_epoch_time_now_ns(DDTRACE_UNUSED VALUE self, VALUE collector_instance);
static VALUE _native_prepare_sample_inside_signal_handler(DDTRACE_UNUSED VALUE self);
static VALUE _native_mark_thread_as_profiler_internal(DDTRACE_UNUSED VALUE self, VALUE thread);
static VALUE _native_remove_per_thread_context_for(DDTRACE_UNUSED VALUE self, VALUE thread);
static VALUE _native_global_reset_per_thread_context(DDTRACE_UNUSED VALUE self, VALUE collector_instance);
static bool skip_sample(thread_context_collector_state *state, per_thread_context *thread_context, bool is_gvl_waiting_state, bool force_sample);
static void on_thread_begin_event(VALUE tracepoint_data, DDTRACE_UNUSED void *unused);

void collectors_thread_context_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_thread_context_class = rb_define_class_under(collectors_module, "ThreadContext", rb_cObject);

  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(collectors_thread_context_class, "Testing");

  // Instances of the ThreadContext class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the thread_context_collector_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(collectors_thread_context_class, _native_new);

  rb_define_singleton_method(collectors_thread_context_class, "_native_initialize", _native_initialize, -1);
  rb_define_singleton_method(collectors_thread_context_class, "_native_inspect", _native_inspect, 1);
  rb_define_singleton_method(collectors_thread_context_class, "_native_reset_after_fork", _native_reset_after_fork, 1);
  rb_define_singleton_method(testing_module, "_native_sample", _native_sample, 2);
  rb_define_singleton_method(testing_module, "_native_sample_allocation", _native_sample_allocation, 3);
  rb_define_singleton_method(testing_module, "_native_on_gc_start", _native_on_gc_start, 1);
  rb_define_singleton_method(testing_module, "_native_on_gc_finish", _native_on_gc_finish, 1);
  rb_define_singleton_method(testing_module, "_native_sample_after_gc", _native_sample_after_gc, 2);
  rb_define_singleton_method(testing_module, "_native_thread_list", _native_thread_list, 0);
  rb_define_singleton_method(testing_module, "_native_per_thread_context", _native_per_thread_context, 1);
  rb_define_singleton_method(testing_module, "_native_stats", _native_stats, 1);
  rb_define_singleton_method(testing_module, "_native_gc_tracking", _native_gc_tracking, 1);
  rb_define_singleton_method(testing_module, "_native_new_empty_thread", _native_new_empty_thread, 0);
  rb_define_singleton_method(testing_module, "_native_sample_skipped_allocation_samples", _native_sample_skipped_allocation_samples, 2);
  rb_define_singleton_method(testing_module, "_native_system_epoch_time_now_ns", _native_system_epoch_time_now_ns, 1);
  rb_define_singleton_method(testing_module, "_native_prepare_sample_inside_signal_handler", _native_prepare_sample_inside_signal_handler, 0);
  rb_define_singleton_method(testing_module, "_native_remove_per_thread_context_for", _native_remove_per_thread_context_for, 1);
  rb_define_singleton_method(testing_module, "_native_global_reset_per_thread_context", _native_global_reset_per_thread_context, 1);
  rb_define_singleton_method(testing_module, "_native_mark_thread_as_profiler_internal", _native_mark_thread_as_profiler_internal, 1);
  #ifndef NO_GVL_INSTRUMENTATION
    rb_define_singleton_method(testing_module, "_native_on_gvl_waiting", _native_on_gvl_waiting, 1);
    rb_define_singleton_method(testing_module, "_native_gvl_waiting_at_for", _native_gvl_waiting_at_for, 1);
    rb_define_singleton_method(testing_module, "_native_on_gvl_running", _native_on_gvl_running, 2);
    rb_define_singleton_method(testing_module, "_native_on_gvl_released", _native_on_gvl_released, 1);
    rb_define_singleton_method(testing_module, "_native_sample_after_gvl_running", _native_sample_after_gvl_running, 3);
  #endif
  rb_define_singleton_method(testing_module, "_native_apply_delta_to_cpu_time_at_previous_sample_ns", _native_apply_delta_to_cpu_time_at_previous_sample_ns, 2);

  at_active_span_id = rb_intern_const("@active_span");
  at_active_trace_id = rb_intern_const("@active_trace");
  at_id_id = rb_intern_const("@id");
  at_resource_id = rb_intern_const("@resource");
  at_root_span_id = rb_intern_const("@root_span");
  at_type_id = rb_intern_const("@type");
  at_otel_values_id = rb_intern_const("@otel_values");
  at_parent_span_id_id = rb_intern_const("@parent_span_id");
  at_datadog_trace_id = rb_intern_const("@datadog_trace");
  at_span_id_id = rb_intern_const("@span_id");
  at_trace_id_id = rb_intern_const("@trace_id");
  at_entries_id = rb_intern_const("@entries");
  at_context_id = rb_intern_const("@context");
  at_kind_id = rb_intern_const("@kind");
  at_name_id = rb_intern_const("@name");
  server_id = rb_intern_const("server");
  otel_context_storage_id = rb_intern_const("__opentelemetry_context_storage__");
  otel_fiber_context_storage_id = rb_intern_const("@opentelemetry_context");

  dd_per_thread_context_id = rb_intern_const("dd_per_thread_context");

  // This will raise if Ruby already ran out of thread-local keys
  per_thread_context_tls_init();

  rb_global_variable(&thread_begin_tracepoint);

  gc_profiling_init();
}

// This structure is used to define a Ruby object that stores a pointer to a thread_context_collector_state
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t thread_context_collector_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Collectors::ThreadContext",
  .function = {
    .dmark = thread_context_collector_typed_data_mark,
    .dfree = thread_context_collector_typed_data_free,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    //.dcompact = NULL, // FIXME: Add support for compaction
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

// This function is called by the Ruby GC to give us a chance to mark any Ruby objects that we're holding on to,
// so that they don't get garbage collected
static void thread_context_collector_typed_data_mark(void *state_ptr) {
  thread_context_collector_state *state = (thread_context_collector_state *) state_ptr;

  // Update this when modifying state struct
  rb_gc_mark(state->recorder_instance);
  rb_gc_mark(state->thread_list_buffer);
  rb_gc_mark(state->main_thread);
  rb_gc_mark(state->otel_current_span_key);
  rb_gc_mark(state->overhead_filename);
}

static void thread_context_collector_typed_data_free(void *state_ptr) {
  thread_context_collector_state *state = (thread_context_collector_state *) state_ptr;

  // Update this when modifying state struct

  // Important: Remember that we're only guaranteed to see here what's been set in _native_new, aka
  // pointers that have been set NULL there may still be NULL here.
  if (state->locations.ptr != NULL) ruby_xfree(state->locations.ptr);

  st_free_table(state->native_filenames_cache);

  ruby_xfree(state);
}

// per_thread_context is wrapped in a TypedData Ruby object stored as an ivar on each Ruby Thread.
// This gives us automatic GC marking (for sampling_buffer iseq VALUEs) and lifecycle management.
static const rb_data_type_t per_thread_context_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::PerThreadContext",
  .function = {
    .dmark = per_thread_context_typed_data_mark,
    .dfree = per_thread_context_typed_data_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static void per_thread_context_typed_data_mark(void *ctx_ptr) {
  per_thread_context *ctx = (per_thread_context *) ctx_ptr;
  if (sampling_buffer_needs_marking(&ctx->sampling_buffer)) {
    sampling_buffer_mark(&ctx->sampling_buffer);
  }
}

static void per_thread_context_typed_data_free(void *ctx_ptr) {
  per_thread_context *ctx = (per_thread_context *) ctx_ptr;
  sampling_buffer_free(&ctx->sampling_buffer);
  free(ctx);
}

// Only for testing: removes the per-thread context without recreating it, so the thread has no context.
// This simulates situations where we observe a thread running before our RUBY_EVENT_THREAD_BEGIN tracepoint fires,
// so that we can test our `get_per_thread_context(...) => null` code paths.
static VALUE _native_remove_per_thread_context_for(DDTRACE_UNUSED VALUE self, VALUE thread) {
  check_frozen_thread(thread);
  per_thread_context *ctx = get_per_thread_context(thread);
  if (ctx != NULL) {
    set_per_thread_context(thread, NULL);
    rb_ivar_set(thread, dd_per_thread_context_id, Qnil);
  }
  return Qnil;
}

static VALUE _native_global_reset_per_thread_context(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  thread_context_collector_reset_all_per_thread_contexts(collector_instance);
  return Qnil;
}

static VALUE _native_new(VALUE klass) {
  thread_context_collector_state *state = ruby_xcalloc(1, sizeof(thread_context_collector_state));

  // Note: Any exceptions raised from this note until the TypedData_Wrap_Struct call will lead to the state memory
  // being leaked.

  // Update this when modifying state struct
  state->locations.ptr = NULL;
  state->locations.len = 0;
  state->recorder_instance = Qnil;
  state->tracer_context_key = MISSING_TRACER_CONTEXT_KEY;
  VALUE thread_list_buffer = rb_ary_new();
  state->thread_list_buffer = thread_list_buffer;
  state->endpoint_collection_enabled = true;
  state->native_filenames_enabled = false;
  state->native_filenames_cache = st_init_numtable();
  state->otel_context_enabled = OTEL_CONTEXT_ENABLED_FALSE;
  state->otel_context_source = OTEL_CONTEXT_SOURCE_UNKNOWN;
  state->time_converter_state = (monotonic_to_system_epoch_state) MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER;
  VALUE main_thread = rb_thread_main();
  state->main_thread = main_thread;
  state->otel_current_span_key = Qtrue;
  state->gc_tracking.wall_time_at_previous_gc_ns = INVALID_TIME;
  state->gc_tracking.wall_time_at_last_flushed_gc_event_ns = 0;

  // Note: Remember to keep any new allocated objects that get stored in the state also on the stack + mark them with
  // RB_GC_GUARD -- otherwise it's possible for a GC to run and
  // since the instance representing the state does not yet exist, such objects will not get marked.

  VALUE instance = TypedData_Wrap_Struct(klass, &thread_context_collector_typed_data, state);

  RB_GC_GUARD(thread_list_buffer);
  RB_GC_GUARD(main_thread); // Arguably not needed, but perhaps can be move in some future Ruby release?

  return instance;
}

static VALUE _native_initialize(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE self_instance = rb_hash_fetch(options, ID2SYM(rb_intern("self_instance")));
  VALUE recorder_instance = rb_hash_fetch(options, ID2SYM(rb_intern("recorder")));
  VALUE max_frames = rb_hash_fetch(options, ID2SYM(rb_intern("max_frames")));
  VALUE tracer_context_key = rb_hash_fetch(options, ID2SYM(rb_intern("tracer_context_key")));
  VALUE endpoint_collection_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("endpoint_collection_enabled")));
  VALUE waiting_for_gvl_threshold_ns = rb_hash_fetch(options, ID2SYM(rb_intern("waiting_for_gvl_threshold_ns")));
  VALUE otel_context_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("otel_context_enabled")));
  VALUE native_filenames_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("native_filenames_enabled")));
  VALUE overhead_filename = rb_hash_fetch(options, ID2SYM(rb_intern("overhead_filename")));

  ENFORCE_TYPE(max_frames, T_FIXNUM);
  ENFORCE_BOOLEAN(endpoint_collection_enabled);
  ENFORCE_TYPE(waiting_for_gvl_threshold_ns, T_FIXNUM);
  ENFORCE_BOOLEAN(native_filenames_enabled);
  ENFORCE_TYPE(overhead_filename, T_STRING);

  uint16_t max_frame_int = sampling_buffer_check_max_frames(NUM2INT(max_frames));

  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  // Update this when modifying state struct
  state->locations.len = max_frame_int;
  state->locations.ptr = ruby_xcalloc(max_frame_int, sizeof(ddog_prof_Location));
  state->recorder_instance = enforce_recorder_instance(recorder_instance);
  recorder_install_on_serialize(recorder_instance, self_instance);
  state->endpoint_collection_enabled = (endpoint_collection_enabled == Qtrue);
  state->native_filenames_enabled = (native_filenames_enabled == Qtrue);
  state->overhead_filename = overhead_filename;
  if (otel_context_enabled == Qfalse || otel_context_enabled == Qnil) {
    state->otel_context_enabled = OTEL_CONTEXT_ENABLED_FALSE;
  } else if (otel_context_enabled == ID2SYM(rb_intern("only"))) {
    state->otel_context_enabled = OTEL_CONTEXT_ENABLED_ONLY;
  } else if (otel_context_enabled == ID2SYM(rb_intern("both"))) {
    state->otel_context_enabled = OTEL_CONTEXT_ENABLED_BOTH;
  } else {
    raise_error(rb_eArgError, "Unexpected value for otel_context_enabled: %+" PRIsVALUE, otel_context_enabled);
  }

  state->waiting_for_gvl_threshold_ns = NUM2UINT(waiting_for_gvl_threshold_ns);

  if (RTEST(tracer_context_key)) {
    ENFORCE_TYPE(tracer_context_key, T_SYMBOL);
    // Note about rb_to_id and dynamic symbols: calling `rb_to_id` prevents symbols from ever being garbage collected.
    // In this case, we can't really escape this because as of this writing, ruby master still calls `rb_to_id` inside
    // the implementation of Thread#[]= so any symbol that gets used as a key there will already be prevented from GC.
    state->tracer_context_key = rb_to_id(tracer_context_key);
  }

  if (thread_begin_tracepoint == Qnil) {
    thread_begin_tracepoint = rb_tracepoint_new(Qnil, RUBY_EVENT_THREAD_BEGIN, on_thread_begin_event, NULL);
    rb_tracepoint_enable(thread_begin_tracepoint);
  }

  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(DDTRACE_UNUSED VALUE _self, VALUE collector_instance, VALUE allow_exception) {
  ENFORCE_BOOLEAN(allow_exception);

  if (allow_exception == Qfalse) debug_enter_unsafe_context();

  thread_context_collector_sample(collector_instance, monotonic_wall_time_now_ns(RAISE_ON_FAILURE));

  if (allow_exception == Qfalse) debug_leave_unsafe_context();

  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_on_gc_start(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  debug_enter_unsafe_context();

  thread_context_collector_on_gc_start(collector_instance);

  debug_leave_unsafe_context();

  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_on_gc_finish(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  debug_enter_unsafe_context();

  (void) !thread_context_collector_on_gc_finish(collector_instance);

  debug_leave_unsafe_context();

  return Qtrue;
}

static VALUE _native_sample_after_gc(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE allow_exception) {
  ENFORCE_BOOLEAN(allow_exception);

  if (allow_exception == Qfalse) debug_enter_unsafe_context();

  thread_context_collector_sample_after_gc(collector_instance);

  if (allow_exception == Qfalse) debug_leave_unsafe_context();

  return Qtrue;
}

// Record profiler sampling overhead as a placeholder stack
static void record_sampling_overhead(thread_context_collector_state *state, per_thread_context *current_thread_context) {
  long wall_time_after_sampling = monotonic_wall_time_now_ns(RAISE_ON_FAILURE);
  long cpu_time_after_sampling = cpu_time_now_ns(current_thread_context);

  long overhead_cpu_time_ns = update_time_since_previous_sample(
    &current_thread_context->cpu_time_at_previous_sample_ns,
    cpu_time_after_sampling,
    current_thread_context->gc_tracking.cpu_time_at_start_ns,
    IS_CPU_TIME);

  long overhead_wall_time_ns = update_time_since_previous_sample(
    &current_thread_context->wall_time_at_previous_sample_ns,
    wall_time_after_sampling,
    INVALID_TIME,
    IS_WALL_TIME);

  ddog_prof_Label overhead_labels[] = {
    {.key = DDOG_CHARSLICE_C("thread id"), .str = DDOG_CHARSLICE_C("0"), .num = 0},
    {.key = DDOG_CHARSLICE_C("thread name"), .str = DDOG_CHARSLICE_C("Datadog::Profiling::Sampling"), .num = 0},
    {.key = DDOG_CHARSLICE_C("state"), .str = DDOG_CHARSLICE_C("had cpu"), .num = 0},
    {.key = DDOG_CHARSLICE_C("profiler overhead"), .num = 1},
  };

  int64_t end_timestamp_ns = monotonic_to_system_epoch_ns(&state->time_converter_state, wall_time_after_sampling);

  ddog_prof_Location overhead_location = {
    .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C(""), .build_id_id = {}},
    .function = {
      .name = DDOG_CHARSLICE_C("sampling"),
      .filename = char_slice_from_ruby_string(state->overhead_filename),
    },
    .line = 0,
  };

  record_sample(
    state->recorder_instance,
    (ddog_prof_Slice_Location) {.ptr = &overhead_location, .len = 1},
    (sample_values) {.cpu_time_ns = overhead_cpu_time_ns, .cpu_or_wall_samples = 1, .wall_time_ns = overhead_wall_time_ns},
    (sample_labels) {
      .labels = (ddog_prof_Slice_Label) {.ptr = overhead_labels, .len = sizeof(overhead_labels) / sizeof(overhead_labels[0])},
      .state_label = NULL,
      .end_timestamp_ns = end_timestamp_ns,
    }
  );
}

// This function gets called from the Collectors::CpuAndWallTimeWorker to trigger the actual sampling.
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is allowed to raise exceptions. Caller is responsible for handling them, if needed.
// Assumption 3: This function IS NOT called from a signal handler. This function is not async-signal-safe.
// Assumption 4: This function IS NOT called in a reentrant way.
// Assumption 5: This function is called from the main Ractor (if Ruby has support for Ractors).
//
void thread_context_collector_sample(VALUE self_instance, long current_monotonic_wall_time_ns) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  VALUE current_thread = rb_thread_current();
  per_thread_context *current_thread_context = get_or_create_context_for(current_thread);
  long cpu_time_at_sample_start_for_current_thread = cpu_time_now_ns(current_thread_context);

  VALUE threads = thread_list(state);

  const long thread_count = RARRAY_LEN(threads);
  for (long i = 0; i < thread_count; i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    per_thread_context *thread_context = get_or_create_context_for(thread);

    // We account for cpu-time for the current thread in a different way: we use the cpu-time at sampling start,
    // to avoid blaming the time the profiler took on whatever is currently running on the thread,
    // and instead we report that time the profiler took as sampling overhead below.
    long current_cpu_time_ns = (thread == current_thread) ? cpu_time_at_sample_start_for_current_thread : cpu_time_now_ns(thread_context);

    update_metrics_and_sample(
      state,
      thread,
      thread_context,
      current_cpu_time_ns,
      current_monotonic_wall_time_ns,
      false);
  }

  state->stats.sample_count++;

  // If the current thread is a profiler-internal thread, we don't use record_sampling_overhead()
  // and accept the sampling overhead is attributed to the profiler-internal thread
  // (both are under the same datadog group in the flamegraph).
  // The reason we need to do this is profiler-internal threads are skipped during per-tick sampling
  // so their timestamps are not updated. record_sampling_overhead() would see the stale previous-sample timestamps and
  // attribute the entire sleep interval incorrectly as overhead instead of just the sampling work.
  if (!current_thread_context->is_profiler_internal_thread) {
    record_sampling_overhead(state, current_thread_context);
  }
}

static void update_metrics_and_sample(
  thread_context_collector_state *state,
  VALUE thread_being_sampled,
  per_thread_context *thread_context,
  long current_cpu_time_ns,
  long current_monotonic_wall_time_ns,
  bool force_sample
) {
  bool is_gvl_waiting_state =
    handle_gvl_waiting(state, thread_being_sampled, thread_context, current_cpu_time_ns);

  if (skip_sample(state, thread_context, is_gvl_waiting_state, force_sample)) return;

  // Don't assign/update cpu during "Waiting for GVL"
  long cpu_time_elapsed_ns = is_gvl_waiting_state ? 0 : update_time_since_previous_sample(
    &thread_context->cpu_time_at_previous_sample_ns,
    current_cpu_time_ns,
    thread_context->gc_tracking.cpu_time_at_start_ns,
    IS_CPU_TIME
  );

  long wall_time_elapsed_ns = update_time_since_previous_sample(
    &thread_context->wall_time_at_previous_sample_ns,
    current_monotonic_wall_time_ns,
    INVALID_TIME,
    IS_WALL_TIME
  );

  // A thread enters "Waiting for GVL", well, as the name implies, without the GVL.
  //
  // As a consequence, it's possible that a thread enters "Waiting for GVL" in parallel with the current thread working
  // on sampling, and thus for the `current_monotonic_wall_time_ns` (which is recorded at the start of sampling)
  // to be < the time at which we started Waiting for GVL.
  //
  // All together, this means that when `handle_gvl_waiting` creates an extra sample (see comments on that function for
  // what the extra sample is), it's possible that there's no more wall-time to be assigned.
  // Thus, in this case, we don't want to produce a sample representing Waiting for GVL with a wall-time of 0, and
  // thus we skip creating such a sample.
  if (is_gvl_waiting_state && wall_time_elapsed_ns == 0) return;
  // ...you may also wonder: is there any other situation where it makes sense to produce a sample with
  // wall_time_elapsed_ns == 0? I believe that yes, because the sample still includes a timestamp and a stack, but we
  // may revisit/change our minds on this in the future.

  trigger_sample_for_thread(
    state,
    thread_being_sampled,
    thread_context,
    (sample_values) {.cpu_time_ns = cpu_time_elapsed_ns, .cpu_or_wall_samples = 1, .wall_time_ns = wall_time_elapsed_ns},
    current_monotonic_wall_time_ns,
    NULL,
    NULL,
    is_gvl_waiting_state,
    /* is_safe_to_allocate_objects: */ true // We called from a context that's safe to run any regular code, including allocations
  );
}

static bool skip_sample(thread_context_collector_state *state, per_thread_context *thread_context, bool is_gvl_waiting_state, bool force_sample) {
  if (!force_sample && thread_context->is_profiler_internal_thread) {
    state->stats.profiler_thread_samples_skipped++;
    return true;
  }

  // Racy read but harmless, can only cause an extra sample
  uint64_t gvl_state_change_count = thread_context->gvl_state_change_count;

  // Skip this per-tick sample entirely when the thread does not have the GVL and did not acquire
  // it since the previous sample: its Ruby-level stack has not changed. The skipped wall-time will
  // be picked up by either by an extra sample when the thread acquires the GVL, or by
  // the on-serialize flush in the stack recorder (using was_skipped_at_last_sample).
  // The check is gated by `!is_gvl_waiting_state` so the existing "Waiting for GVL" machinery
  // in handle_gvl_waiting (situation 1 extra sample, situation 2 regular sample) keeps running.
  // TODO: we could probably also skip while "Waiting for GVL"
  if (!is_gvl_waiting_state &&
      !force_sample &&
      (gvl_state_change_count & GVL_SUSPENDED) &&
      gvl_state_change_count == thread_context->gvl_state_change_count_at_previous_sample) {
    state->stats.inactive_thread_samples_skipped++;
    thread_context->was_skipped_at_last_sample = true;
    return true; // Do NOT update wall_time_at_previous_sample_ns or cpu_time_at_previous_sample_ns
  } else {
    // We are going to sample, update the state accordingly:
    thread_context->gvl_state_change_count_at_previous_sample = gvl_state_change_count;
    thread_context->was_skipped_at_last_sample = false;
    return false;
  }
}

// This function gets called when Ruby is about to start running the Garbage Collector on the current thread.
// It updates the per_thread_context of the current thread to include the current cpu/wall times, to be used to later
// create an event including the cpu/wall time spent in garbage collector work.
//
// Safety: This function gets called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is called from the main Ractor (if Ruby has support for Ractors).
void thread_context_collector_on_gc_start(VALUE self_instance) {
  thread_context_collector_state *state;
  if (!rb_typeddata_is_kind_of(self_instance, &thread_context_collector_typed_data)) return;
  // This should never fail when the above check passes
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  per_thread_context *thread_context = get_per_thread_context(rb_thread_current());

  // Context is created eagerly via on_thread_begin_event, so this should not normally be NULL.
  // We can't get_or_create_context_for() here since we can't allocate (GC context).
  if (thread_context == NULL) {
    state->stats.gc_samples_missed_due_to_missing_context++;
    return;
  }

  // Here we record the wall-time first and in on_gc_finish we record it second to try to avoid having wall-time be slightly < cpu-time
  thread_context->gc_tracking.wall_time_at_start_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);
  thread_context->gc_tracking.cpu_time_at_start_ns = cpu_time_now_ns(thread_context);
}

// This function gets called when Ruby has finished running the Garbage Collector on the current thread.
// It records the cpu/wall-time observed during GC, which will be used to later
// create an event including the cpu/wall time spent from the start of garbage collector work until now.
//
// Safety: This function gets called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is called from the main Ractor (if Ruby has support for Ractors).
__attribute__((warn_unused_result))
bool thread_context_collector_on_gc_finish(VALUE self_instance) {
  thread_context_collector_state *state;
  if (!rb_typeddata_is_kind_of(self_instance, &thread_context_collector_typed_data)) return false;
  // This should never fail when the above check passes
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  per_thread_context *thread_context = get_per_thread_context(rb_thread_current());

  // Context is created eagerly, so this should not normally be NULL (see on_gc_start).
  if (thread_context == NULL) return false;

  long cpu_time_at_start_ns = thread_context->gc_tracking.cpu_time_at_start_ns;
  long wall_time_at_start_ns = thread_context->gc_tracking.wall_time_at_start_ns;

  if (cpu_time_at_start_ns == INVALID_TIME && wall_time_at_start_ns == INVALID_TIME) {
    // If this happened, it means that on_gc_start was either never called for the thread OR it was called but no thread
    // context existed at the time. The former can be the result of a bug, but since we can't distinguish them, we just
    // do nothing.
    return false;
  }

  // Mark thread as no longer in GC
  thread_context->gc_tracking.cpu_time_at_start_ns = INVALID_TIME;
  thread_context->gc_tracking.wall_time_at_start_ns = INVALID_TIME;

  // Here we record the wall-time second and in on_gc_start we record it first to try to avoid having wall-time be slightly < cpu-time
  long cpu_time_at_finish_ns = cpu_time_now_ns(thread_context);
  long wall_time_at_finish_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);

  // If our end timestamp is not OK, we bail out
  if (wall_time_at_finish_ns == 0) return false;

  long gc_cpu_time_elapsed_ns = cpu_time_at_finish_ns - cpu_time_at_start_ns;
  long gc_wall_time_elapsed_ns = wall_time_at_finish_ns - wall_time_at_start_ns;

  // Wall-time can go backwards if the system clock gets changed (and we observed spurious jumps back on macOS as well)
  // so let's ensure we don't get negative values for time deltas.
  gc_cpu_time_elapsed_ns = long_max_of(gc_cpu_time_elapsed_ns, 0);
  gc_wall_time_elapsed_ns = long_max_of(gc_wall_time_elapsed_ns, 0);

  if (state->gc_tracking.wall_time_at_previous_gc_ns == INVALID_TIME) {
    state->gc_tracking.accumulated_cpu_time_ns = 0;
    state->gc_tracking.accumulated_wall_time_ns = 0;
  }

  state->gc_tracking.accumulated_cpu_time_ns += gc_cpu_time_elapsed_ns;
  state->gc_tracking.accumulated_wall_time_ns += gc_wall_time_elapsed_ns;
  state->gc_tracking.wall_time_at_previous_gc_ns = wall_time_at_finish_ns;

  // Update cpu-time accounting so it doesn't include the cpu-time spent in GC during the next sample
  // We don't update the wall-time because we don't subtract the wall-time spent in GC (see call to
  // `update_time_since_previous_sample` for wall-time in `update_metrics_and_sample`).
  if (thread_context->cpu_time_at_previous_sample_ns != INVALID_TIME) {
    thread_context->cpu_time_at_previous_sample_ns += gc_cpu_time_elapsed_ns;
  }

  // Let the caller know if it should schedule a flush or not. Returning true every time would cause a lot of overhead
  // on the application (see GC tracking introduction at the top of the file), so instead we try to accumulate a few
  // samples first.
  bool over_flush_time_treshold =
    (wall_time_at_finish_ns - state->gc_tracking.wall_time_at_last_flushed_gc_event_ns) >= TIME_BETWEEN_GC_EVENTS_NS;

  if (over_flush_time_treshold) {
    return true;
  } else {
    return gc_profiling_has_major_gc_finished();
  }
}

// This function gets called after one or more GC work steps (calls to on_gc_start/on_gc_finish).
// It creates a new sample including the cpu and wall-time spent by the garbage collector work, and resets any
// GC-related tracking.
//
// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
// Assumption 2: This function is allowed to raise exceptions. Caller is responsible for handling them, if needed.
// Assumption 3: Unlike `on_gc_start` and `on_gc_finish`, this method is allowed to allocate memory as needed.
// Assumption 4: This function is called from the main Ractor (if Ruby has support for Ractors).
VALUE thread_context_collector_sample_after_gc(VALUE self_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  if (state->gc_tracking.wall_time_at_previous_gc_ns == INVALID_TIME) {
    raise_error(rb_eRuntimeError, "BUG: Unexpected call to sample_after_gc without valid GC information available");
  }

  int max_labels_needed_for_gc = 7; // Magic number gets validated inside gc_profiling_set_metadata
  ddog_prof_Label labels[max_labels_needed_for_gc];
  uint8_t label_pos = gc_profiling_set_metadata(labels, max_labels_needed_for_gc);

  ddog_prof_Slice_Label slice_labels = {.ptr = labels, .len = label_pos};

  // The end_timestamp_ns is treated specially by libdatadog and that's why it's not added as a ddog_prof_Label
  int64_t end_timestamp_ns = monotonic_to_system_epoch_ns(&state->time_converter_state, state->gc_tracking.wall_time_at_previous_gc_ns);

  record_placeholder_stack(
    state->recorder_instance,
    (sample_values) {
      // This event gets both a regular cpu/wall-time duration, as a normal cpu/wall-time sample would, as well as a
      // timeline duration.
      // This is done to enable two use-cases:
      // * regular cpu/wall-time makes this event show up as a regular stack in the flamegraph
      // * the timeline duration is used when the event shows up in the timeline
      .cpu_time_ns = state->gc_tracking.accumulated_cpu_time_ns,
      .cpu_or_wall_samples = 1,
      .wall_time_ns = state->gc_tracking.accumulated_wall_time_ns,
      .timeline_wall_time_ns = state->gc_tracking.accumulated_wall_time_ns,
    },
    (sample_labels) {.labels = slice_labels, .state_label = NULL, .end_timestamp_ns = end_timestamp_ns},
    DDOG_CHARSLICE_C("Garbage Collection")
  );

  state->gc_tracking.wall_time_at_last_flushed_gc_event_ns = state->gc_tracking.wall_time_at_previous_gc_ns;
  state->gc_tracking.wall_time_at_previous_gc_ns = INVALID_TIME;

  state->stats.gc_samples++;

  // Let recorder do any cleanup/updates it requires after a GC step.
  recorder_after_gc_step(state->recorder_instance);

  // Return a VALUE to make it easier to call this function from Ruby APIs that expect a return value (such as rb_rescue2)
  return Qnil;
}

static void trigger_sample_for_thread(
  thread_context_collector_state *state,
  VALUE thread_being_sampled,
  per_thread_context *thread_context,
  sample_values values,
  long current_monotonic_wall_time_ns,
  // These two labels are only used for allocation profiling; @ivoanjo: may want to refactor this at some point?
  ddog_CharSlice *ruby_vm_type,
  ddog_CharSlice *class_name,
  bool is_gvl_waiting_state,
  // If the Ruby VM is at a state that can allocate objects safely, or not. Added for allocation profiling: we're not
  // allowed to allocate objects (or raise exceptions) when inside the NEWOBJ tracepoint.
  bool is_safe_to_allocate_objects
) {
  int max_label_count =
    1 + // thread id
    1 + // thread name
    2 + // ruby vm type and allocation class
    1 + // state (only set for cpu/wall-time samples)
    2;  // local root span id and span id
  ddog_prof_Label labels[max_label_count];
  int label_pos = 0;

  labels[label_pos++] = (ddog_prof_Label) {
    .key = DDOG_CHARSLICE_C("thread id"),
    .str = thread_context->thread_id_char_slice
  };

  VALUE thread_name = thread_name_for(thread_being_sampled);
  if (thread_name != Qnil) {
    labels[label_pos++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("thread name"),
      .str = char_slice_from_ruby_string(thread_name)
    };
  } else if (thread_being_sampled == state->main_thread) { // Threads are often not named, but we can have a nice fallback for this special thread
    ddog_CharSlice main_thread_name = DDOG_CHARSLICE_C("main");
    labels[label_pos++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("thread name"),
      .str = main_thread_name
    };
  } else {
    // For other threads without name, we use the "invoke location" (first file:line of the block used to start the thread), if any.
    // This is what Ruby shows in `Thread#to_s`.
    labels[label_pos++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("thread name"),
      .str = thread_context->thread_invoke_location_char_slice // This is an empty string if no invoke location was available
    };
  }

  trace_identifiers trace_identifiers_result = {.valid = false, .trace_endpoint = Qnil};
  trace_identifiers_for(state, thread_being_sampled, &trace_identifiers_result, is_safe_to_allocate_objects);

  if (!trace_identifiers_result.valid && state->otel_context_enabled != OTEL_CONTEXT_ENABLED_FALSE) {
    // If we couldn't get something with ddtrace, let's see if we can get some trace identifiers from opentelemetry directly
    otel_without_ddtrace_trace_identifiers_for(state, thread_being_sampled, &trace_identifiers_result, is_safe_to_allocate_objects);
  }

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

  if (ruby_vm_type != NULL) {
    labels[label_pos++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("ruby vm type"),
      .str = *ruby_vm_type
    };
  }

  if (class_name != NULL) {
    labels[label_pos++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("allocation class"),
      .str = *class_name
    };
  }

  // This label is handled specially:
  // 1. It's only set for cpu/wall-time samples
  // 2. We set it here to its default state of "unknown", but the `Collectors::Stack` may choose to override it with
  //    something more interesting.
  ddog_prof_Label *state_label = NULL;
  if (values.cpu_or_wall_samples > 0) {
    state_label = &labels[label_pos++];
    *state_label = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("state"),
      .str = DDOG_CHARSLICE_C("unknown"),
      .num = 0, // This shouldn't be needed but the tracer-2.7 docker image ships a buggy gcc that complains about this
    };
  }

  // The number of times `label_pos++` shows up in this function needs to match `max_label_count`. To avoid "oops I
  // forgot to update max_label_count" in the future, we've also added this validation.
  // @ivoanjo: I wonder if C compilers are smart enough to statically prove this check never triggers unless someone
  // changes the code erroneously and remove it entirely?
  if (label_pos > max_label_count) {
    raise_error(rb_eRuntimeError, "BUG: Unexpected label_pos (%d) > max_label_count (%d)", label_pos, max_label_count);
  }

  ddog_prof_Slice_Label slice_labels = {.ptr = labels, .len = label_pos};

  // The end_timestamp_ns is treated specially by libdatadog and that's why it's not added as a ddog_prof_Label
  int64_t end_timestamp_ns = 0;
  if (current_monotonic_wall_time_ns != INVALID_TIME) {
    end_timestamp_ns = monotonic_to_system_epoch_ns(&state->time_converter_state, current_monotonic_wall_time_ns);
  }

  sample_thread(
    thread_being_sampled,
    &thread_context->sampling_buffer,
    state->locations,
    state->recorder_instance,
    values,
    (sample_labels) {
      .labels = slice_labels,
      .state_label = state_label,
      .end_timestamp_ns = end_timestamp_ns,
      .is_gvl_waiting_state = is_gvl_waiting_state,
    },
    state->native_filenames_enabled,
    state->native_filenames_cache
  );
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_thread_list(DDTRACE_UNUSED VALUE _self) {
  VALUE result = rb_ary_new();

  debug_enter_unsafe_context();

  ddtrace_thread_list(result);

  debug_leave_unsafe_context();

  return result;
}

static void check_frozen_thread(VALUE thread) {
  if (RB_OBJ_FROZEN(thread)) {
    raise_error(rb_eFrozenError, "Cannot setup profiler state for Thread %"PRIsVALUE" because it is frozen. Please avoid freezing Thread instances and/or report the issue to dd-trace-rb", thread);
  }
}

// See the docs on struct per_thread_context.
// This allocates a Ruby object and therefore needs the GVL and is not safe to call from RUBY_INTERNAL_EVENT_* hooks.
static per_thread_context *get_or_create_context_for(VALUE thread) {
  per_thread_context *thread_context = get_per_thread_context(thread);
  if (thread_context != NULL) return thread_context;

  check_frozen_thread(thread);

  thread_context = calloc(1, sizeof(per_thread_context)); // See "note on calloc vs ruby_xcalloc use" in heap_recorder.c
  initialize_context(thread, thread_context);

  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &per_thread_context_typed_data, thread_context);
  rb_ivar_set(thread, dd_per_thread_context_id, wrapper);

  set_per_thread_context(thread, thread_context);
  return thread_context;
}

static void on_thread_begin_event(VALUE tracepoint_data, DDTRACE_UNUSED void *unused) {
  if (!ddtrace_rb_ractor_main_p()) return;

  VALUE thread = rb_tracearg_self(rb_tracearg_from_tracepoint(tracepoint_data));
  ENFORCE_THREAD(thread);
  get_or_create_context_for(thread);
}

#define LOGGING_GEM_PATH "/lib/logging/diagnostic_context.rb"

// The `logging` gem monkey patches thread creation, which makes the `invoke_location_for` useless, since every thread
// will point to the `logging` gem. When that happens, we avoid using the invoke location.
//
// TODO: This approach is a bit brittle, since it matches on the specific gem path, and only works for the `logging`
// gem.
// In the future we should probably explore a more generic fix (e.g. using Thread.method(:new).source_location or
// something like that to detect redefinition of the `Thread` methods). One difficulty of doing it is that we need
// to either run Ruby code during sampling (not great), or otherwise use some of the VM private APIs to detect this.
//
static bool is_logging_gem_monkey_patch(VALUE invoke_file_location) {
  unsigned long logging_gem_path_len = strlen(LOGGING_GEM_PATH);
  char *invoke_file = StringValueCStr(invoke_file_location);
  unsigned long invoke_file_len = strlen(invoke_file);

  if (invoke_file_len < logging_gem_path_len) return false;

  return strncmp(invoke_file + invoke_file_len - logging_gem_path_len, LOGGING_GEM_PATH, logging_gem_path_len) == 0;
}

static void initialize_context(VALUE thread, per_thread_context *thread_context) {
  // We always create per_thread_context's with latest_max_frames; that value is kept in sync with the
  // active profiler's max_frames by the global reset that runs when profiling starts
  // so we expect to always see here the latest correct value to be used.
  sampling_buffer_initialize(&thread_context->sampling_buffer, latest_max_frames);

  snprintf(thread_context->thread_id, THREAD_ID_LIMIT_CHARS, "%"PRIu64" (%lu)", native_thread_id_for(thread), (unsigned long) thread_id_for(thread));
  thread_context->thread_id_char_slice = (ddog_CharSlice) {.ptr = thread_context->thread_id, .len = strlen(thread_context->thread_id)};

  int invoke_line_location;
  VALUE invoke_file_location = invoke_location_for(thread, &invoke_line_location);
  if (invoke_file_location != Qnil) {
    if (!is_logging_gem_monkey_patch(invoke_file_location)) {
      snprintf(
        thread_context->thread_invoke_location,
        THREAD_INVOKE_LOCATION_LIMIT_CHARS,
        "%s:%d",
        StringValueCStr(invoke_file_location),
        invoke_line_location
      );
    } else {
      snprintf(thread_context->thread_invoke_location, THREAD_INVOKE_LOCATION_LIMIT_CHARS, "%s", "(Unnamed thread)");
    }
  } else if (thread != rb_thread_main()) {
    // If the first function of a thread is native code, there won't be an invoke location, so we use this fallback.
    // NOTE: In the future, I wonder if we could take the pointer to the native function, and try to see if there's a native
    // symbol attached to it.
    snprintf(thread_context->thread_invoke_location, THREAD_INVOKE_LOCATION_LIMIT_CHARS, "%s", "(Unnamed thread from native code)");
  }

  thread_context->thread_invoke_location_char_slice = (ddog_CharSlice) {
    .ptr = thread_context->thread_invoke_location,
    .len = strlen(thread_context->thread_invoke_location)
  };

  thread_context->thread_cpu_time_id = thread_cpu_time_id_for(thread);

  thread_context->wall_time_at_previous_sample_ns = monotonic_wall_time_now_ns(RAISE_ON_FAILURE);
  thread_context->cpu_time_at_previous_sample_ns = cpu_time_now_ns(thread_context);

  // These will only be used during a GC operation
  thread_context->gc_tracking.cpu_time_at_start_ns = INVALID_TIME;
  thread_context->gc_tracking.wall_time_at_start_ns = INVALID_TIME;

  thread_context->gvl_waiting_at = 0;
  thread_context->gvl_state_change_count = 0;
}

// This MUST be called before profiling starts, so that a new profiler session starts from a fresh state and never
// observes or includes any leftover stale state from a previous session.
// Such a call MUST happen while the CpuAndWallTimeWorker is stopped (e.g. no tracepoints active, no signals
// triggering samples, no gvl hooks, etc).
//
// It updates the global `latest_max_frames` from the given (latest) ThreadContext and (re)creates every per-thread
// context's sampling buffer sized accordingly, so the buffers always match the collector that's about to start
// sampling -- even if a previous session used a different max_frames.
void thread_context_collector_reset_all_per_thread_contexts(VALUE self_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  // Update global max frames to be used when allocating sampling buffers
  if (state->locations.len == 0) {
    raise_error(rb_eRuntimeError, "BUG: Unexpected locations.len == 0. Is this ThreadContext not initialized?");
  }

  latest_max_frames = state->locations.len;

  VALUE threads = thread_list(state);
  const long thread_count = RARRAY_LEN(threads);
  for (long i = 0; i < thread_count; i++) {
    VALUE thread = rb_ary_entry(threads, i);
    per_thread_context *thread_context = get_per_thread_context(thread);
    if (thread_context != NULL) {
      bool is_profiler_internal_thread = thread_context->is_profiler_internal_thread;

      sampling_buffer_free(&thread_context->sampling_buffer);
      memset(thread_context, 0, sizeof(per_thread_context));
      initialize_context(thread, thread_context);

      thread_context->is_profiler_internal_thread = is_profiler_internal_thread;
    } else {
      // If thread didn't have a context, let's trigger its creation
      get_or_create_context_for(thread);
    }
  }
}

static VALUE _native_inspect(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(collector_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  VALUE result = rb_str_new2(" (native state)");

  // Update this when modifying state struct
  rb_str_concat(result, rb_sprintf(" max_frames=%d", state->locations.len));
  rb_str_concat(result, rb_sprintf(" recorder_instance=%"PRIsVALUE, state->recorder_instance));
  VALUE tracer_context_key = state->tracer_context_key == MISSING_TRACER_CONTEXT_KEY ? Qnil : ID2SYM(state->tracer_context_key);
  rb_str_concat(result, rb_sprintf(" tracer_context_key=%+"PRIsVALUE, tracer_context_key));
  rb_str_concat(result, rb_sprintf(" stats=%"PRIsVALUE, stats_to_ruby_hash(state, rb_hash_new())));
  rb_str_concat(result, rb_sprintf(" endpoint_collection_enabled=%"PRIsVALUE, state->endpoint_collection_enabled ? Qtrue : Qfalse));
  rb_str_concat(result, rb_sprintf(" native_filenames_enabled=%"PRIsVALUE, state->native_filenames_enabled ? Qtrue : Qfalse));
  // Note: `st_table_size()` is available from Ruby 3.2+ but not before
  rb_str_concat(result, rb_sprintf(" native_filenames_cache_size=%zu", state->native_filenames_cache->num_entries));
  rb_str_concat(result, rb_sprintf(" otel_context_enabled=%d", state->otel_context_enabled));
  rb_str_concat(result, rb_sprintf(
    " time_converter_state={.system_epoch_ns_reference=%ld, .delta_to_epoch_ns=%ld}",
    state->time_converter_state.system_epoch_ns_reference,
    state->time_converter_state.delta_to_epoch_ns
  ));
  rb_str_concat(result, rb_sprintf(" main_thread=%"PRIsVALUE, state->main_thread));
  rb_str_concat(result, rb_sprintf(" gc_tracking=%"PRIsVALUE, gc_tracking_as_ruby_hash(state)));
  rb_str_concat(result, rb_sprintf(" otel_current_span_key=%"PRIsVALUE, state->otel_current_span_key));
  rb_str_concat(result, rb_sprintf(" waiting_for_gvl_threshold_ns=%u", state->waiting_for_gvl_threshold_ns));

  return result;
}

static VALUE per_thread_context_to_ruby_hash(per_thread_context *thread_context) {
  VALUE context_as_hash = rb_hash_new();

  VALUE arguments[] = {
    ID2SYM(rb_intern("thread_id")),                       /* => */ rb_str_new2(thread_context->thread_id),
    ID2SYM(rb_intern("thread_invoke_location")),          /* => */ rb_str_new2(thread_context->thread_invoke_location),
    ID2SYM(rb_intern("thread_cpu_time_id_valid?")),       /* => */ thread_context->thread_cpu_time_id.valid ? Qtrue : Qfalse,
    #ifdef __APPLE__
      ID2SYM(rb_intern("thread_cpu_time_id")),              /* => */ ULL2NUM(thread_context->thread_cpu_time_id.clock_id),
    #else
      ID2SYM(rb_intern("thread_cpu_time_id")),              /* => */ CLOCKID2NUM(thread_context->thread_cpu_time_id.clock_id),
    #endif
    ID2SYM(rb_intern("cpu_time_at_previous_sample_ns")),  /* => */ LONG2NUM(thread_context->cpu_time_at_previous_sample_ns),
    ID2SYM(rb_intern("wall_time_at_previous_sample_ns")), /* => */ LONG2NUM(thread_context->wall_time_at_previous_sample_ns),

    ID2SYM(rb_intern("gc_tracking.cpu_time_at_start_ns")),   /* => */ LONG2NUM(thread_context->gc_tracking.cpu_time_at_start_ns),
    ID2SYM(rb_intern("gc_tracking.wall_time_at_start_ns")),  /* => */ LONG2NUM(thread_context->gc_tracking.wall_time_at_start_ns),

    ID2SYM(rb_intern("gvl_waiting_at")), /* => */ LONG2NUM(thread_context->gvl_waiting_at),
    ID2SYM(rb_intern("gvl_state_change_count")), /* => */ ULL2NUM(thread_context->gvl_state_change_count),
    ID2SYM(rb_intern("gvl_state_change_count_at_previous_sample")), /* => */ ULL2NUM(thread_context->gvl_state_change_count_at_previous_sample),
    ID2SYM(rb_intern("was_skipped_at_last_sample")), /* => */ thread_context->was_skipped_at_last_sample ? Qtrue : Qfalse,
    ID2SYM(rb_intern("is_profiler_internal_thread")), /* => */ thread_context->is_profiler_internal_thread ? Qtrue : Qfalse,
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(context_as_hash, arguments[i], arguments[i+1]);

  return context_as_hash;
}

static VALUE stats_to_ruby_hash(thread_context_collector_state *state, VALUE hash) {
  // Update this when modifying state struct (stats inner struct)
  VALUE arguments[] = {
    ID2SYM(rb_intern("sample_count")),                             /* => */ UINT2NUM(state->stats.sample_count),
    ID2SYM(rb_intern("gc_samples")),                               /* => */ UINT2NUM(state->stats.gc_samples),
    ID2SYM(rb_intern("gc_samples_missed_due_to_missing_context")), /* => */ UINT2NUM(state->stats.gc_samples_missed_due_to_missing_context),
    ID2SYM(rb_intern("inactive_thread_samples_skipped")),          /* => */ UINT2NUM(state->stats.inactive_thread_samples_skipped),
    ID2SYM(rb_intern("profiler_thread_samples_skipped")),          /* => */ UINT2NUM(state->stats.profiler_thread_samples_skipped),
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(hash, arguments[i], arguments[i+1]);
  return hash;
}

static VALUE gc_tracking_as_ruby_hash(thread_context_collector_state *state) {
  // Update this when modifying state struct (gc_tracking inner struct)
  VALUE result = rb_hash_new();
  VALUE arguments[] = {
    ID2SYM(rb_intern("accumulated_cpu_time_ns")),               /* => */ ULONG2NUM(state->gc_tracking.accumulated_cpu_time_ns),
    ID2SYM(rb_intern("accumulated_wall_time_ns")),              /* => */ ULONG2NUM(state->gc_tracking.accumulated_wall_time_ns),
    ID2SYM(rb_intern("wall_time_at_previous_gc_ns")),           /* => */ LONG2NUM(state->gc_tracking.wall_time_at_previous_gc_ns),
    ID2SYM(rb_intern("wall_time_at_last_flushed_gc_event_ns")), /* => */ LONG2NUM(state->gc_tracking.wall_time_at_last_flushed_gc_event_ns),
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(result, arguments[i], arguments[i+1]);
  return result;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
//
// Returns the whole contents of the per_thread_context structs being tracked, by iterating all live threads.
static VALUE _native_per_thread_context(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(collector_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  VALUE result = rb_hash_new();
  VALUE threads = thread_list(state);
  const long thread_count = RARRAY_LEN(threads);
  for (long i = 0; i < thread_count; i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    per_thread_context *thread_context = get_per_thread_context(thread);
    if (thread_context != NULL) {
      rb_hash_aset(result, thread, per_thread_context_to_ruby_hash(thread_context));
    }
  }
  return result;
}

// gc_start_time_ns should only be passed if IS_CPU_TIME
static long update_time_since_previous_sample(long *time_at_previous_sample_ns, long current_time_ns, long gc_start_time_ns, bool is_wall_time) {
  // If we didn't have a time for the previous sample, we use the current one
  if (*time_at_previous_sample_ns == INVALID_TIME) *time_at_previous_sample_ns = current_time_ns;

  // We don't want wall-time accounting to change during GC.
  // E.g. if 60 seconds pass in the real world, 60 seconds of wall-time are recorded, regardless of the thread doing GC or not.
  bool is_thread_doing_gc = !is_wall_time && gc_start_time_ns != INVALID_TIME;
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
      raise_error(rb_eRuntimeError, "BUG: Unexpected negative elapsed_time_ns between samples");
    }
  }

  return elapsed_time_ns;
}

// Safety: This function is assumed never to raise exceptions by callers
static long cpu_time_now_ns(per_thread_context *thread_context) {
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

VALUE enforce_thread_context_collector_instance(VALUE object) {
  ENFORCE_TYPED_DATA(object, &thread_context_collector_typed_data);
  return object;
}

// Finalize any pending heap allocation recordings.
// On Ruby 4+, heap allocations are recorded in two phases: during on_newobj_event we capture
// the object reference, then later we safely call rb_obj_id() to get the object ID.
void thread_context_collector_after_allocation(VALUE self_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  recorder_after_sample(state->recorder_instance);
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_stats(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(collector_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  return stats_to_ruby_hash(state, rb_hash_new());
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_gc_tracking(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(collector_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  return gc_tracking_as_ruby_hash(state);
}

// Assumption 1: This function is called in a thread that is holding the Global VM Lock. Caller is responsible for enforcing this.
static void trace_identifiers_for(
  thread_context_collector_state *state,
  VALUE thread,
  trace_identifiers *trace_identifiers_result,
  bool is_safe_to_allocate_objects
) {
  if (state->otel_context_enabled == OTEL_CONTEXT_ENABLED_ONLY) return;
  if (state->tracer_context_key == MISSING_TRACER_CONTEXT_KEY) return;

  VALUE current_context = rb_thread_local_aref(thread, state->tracer_context_key);
  if (current_context == Qnil) return;

  VALUE active_trace = rb_ivar_get(current_context, at_active_trace_id /* @active_trace */);
  if (active_trace == Qnil) return;

  VALUE root_span = rb_ivar_get(active_trace, at_root_span_id /* @root_span */);
  VALUE active_span = rb_ivar_get(active_trace, at_active_span_id /* @active_span */);
  // Note: On Ruby 3.x `rb_attr_get` is exactly the same as `rb_ivar_get`. For Ruby 2.x, the difference is that
  // `rb_ivar_get` can trigger "warning: instance variable @otel_values not initialized" if warnings are enabled and
  // opentelemetry is not in use, whereas `rb_attr_get` does the lookup without generating the warning.
  VALUE otel_values = rb_attr_get(active_trace, at_otel_values_id /* @otel_values */);

  VALUE numeric_span_id = Qnil;

  if (otel_values != Qnil) {
    ddtrace_otel_trace_identifiers_for(state, &active_trace, &root_span, &numeric_span_id, active_span, otel_values, is_safe_to_allocate_objects);
  }

  if (root_span == Qnil || (active_span == Qnil && numeric_span_id == Qnil)) return;

  VALUE numeric_local_root_span_id = rb_ivar_get(root_span, at_id_id /* @id */);
  if (active_span != Qnil && numeric_span_id == Qnil) numeric_span_id = rb_ivar_get(active_span, at_id_id /* @id */);
  if (numeric_local_root_span_id == Qnil || numeric_span_id == Qnil) return;

  trace_identifiers_result->local_root_span_id = NUM2ULL(numeric_local_root_span_id);
  trace_identifiers_result->span_id = NUM2ULL(numeric_span_id);

  trace_identifiers_result->valid = true;

  if (!state->endpoint_collection_enabled || !should_collect_resource(root_span)) return;

  VALUE trace_resource = rb_ivar_get(active_trace, at_resource_id /* @resource */);
  if (RB_TYPE_P(trace_resource, T_STRING)) {
    trace_identifiers_result->trace_endpoint = trace_resource;
  } else if (trace_resource == Qnil) {
    // Fall back to resource from span, if any
    trace_identifiers_result->trace_endpoint = rb_ivar_get(root_span, at_resource_id /* @resource */);
  }
}

// We opt-in to collecting the resource for spans of types:
// * 'web', for web requests
// * 'proxy', used by the rack integration with request_queuing: true (e.g. also represents a web request)
// * 'worker', used for sidekiq and similar background job processors
//
// Over time, this list may be expanded.
// Resources MUST NOT include personal identifiable information (PII); this should not be the case with
// ddtrace integrations, but worth mentioning just in case :)
static bool should_collect_resource(VALUE root_span) {
  VALUE root_span_type = rb_ivar_get(root_span, at_type_id /* @type */);
  if (root_span_type == Qnil) return false;
  ENFORCE_TYPE(root_span_type, T_STRING);

  long root_span_type_length = RSTRING_LEN(root_span_type);
  const char *root_span_type_value = StringValuePtr(root_span_type);

  bool is_web_request =
    (root_span_type_length == strlen("web") && (memcmp("web", root_span_type_value, strlen("web")) == 0)) ||
    (root_span_type_length == strlen("proxy") && (memcmp("proxy", root_span_type_value, strlen("proxy")) == 0));

  if (is_web_request) return true;

  bool is_worker_request =
    (root_span_type_length == strlen("worker") && (memcmp("worker", root_span_type_value, strlen("worker")) == 0));

  return is_worker_request;
}

// After the Ruby VM forks, this method gets called in the child process to clean up any leftover state from the parent.
//
// Assumption: This method gets called BEFORE restarting profiling -- e.g. there are no components attempting to
// trigger samples at the same time.
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(collector_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  state->stats = (struct stats) {}; // Resets all stats back to zero

  // No need to clean-up the per-thread context because the CpuAndWallTimeWorker always cleans
  // it up unconditionally on every start/restart and that includes after a fork.

  rb_funcall(state->recorder_instance, rb_intern("reset_after_fork"), 0);

  return Qtrue;
}

static VALUE thread_list(thread_context_collector_state *state) {
  VALUE result = state->thread_list_buffer;
  rb_ary_clear(result);
  ddtrace_thread_list(result);
  return result;
}

// Inside a signal handler, we don't want to do the whole work of recording a sample, but we only record the stack of
// the current thread.
//
// Assumptions for this function are same as for `thread_context_collector_sample` except that this function is
// expected to be called from a signal handler and to be async-signal-safe.
//
// Also, no allocation (Ruby or malloc) can happen.
bool thread_context_collector_prepare_sample_inside_signal_handler(void) {
  VALUE current_thread = rb_thread_current();
  per_thread_context *thread_context = get_per_thread_context(current_thread);
  if (thread_context == NULL) return false;

  return prepare_sample_thread(current_thread, &thread_context->sampling_buffer);
}

// This method gets called from inside the RUBY_INTERNAL_EVENT_NEWOBJ tracepoint so it should never allocate in the
// Ruby heap.
//
// Returns true if the after_allocation needs to be called (to do work that can't be done from inside the
// tracepoint, such as allocate new objects), and false if it doesn't
//
// The callers must ensure thread_context is non-NULL.
bool thread_context_collector_sample_allocation(VALUE self_instance, per_thread_context *thread_context, unsigned int sample_weight, VALUE new_object) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  enum ruby_value_type type = rb_type(new_object);

  // Tag samples with the VM internal types
  ddog_CharSlice ruby_vm_type = ruby_value_type_to_char_slice(type);

  // Since this is stack allocated, be careful about moving it
  ddog_CharSlice class_name;
  char imemo_type[100];

  if (
    type == RUBY_T_OBJECT   ||
    type == RUBY_T_CLASS    ||
    type == RUBY_T_MODULE   ||
    type == RUBY_T_FLOAT    ||
    type == RUBY_T_STRING   ||
    type == RUBY_T_REGEXP   ||
    type == RUBY_T_ARRAY    ||
    type == RUBY_T_HASH     ||
    type == RUBY_T_STRUCT   ||
    type == RUBY_T_BIGNUM   ||
    type == RUBY_T_FILE     ||
    type == RUBY_T_DATA     ||
    type == RUBY_T_MATCH    ||
    type == RUBY_T_COMPLEX  ||
    type == RUBY_T_RATIONAL ||
    type == RUBY_T_NIL      ||
    type == RUBY_T_TRUE     ||
    type == RUBY_T_FALSE    ||
    type == RUBY_T_SYMBOL   ||
    type == RUBY_T_FIXNUM
  ) {
    VALUE klass = rb_class_of(new_object);

    // Ruby sometimes plays a bit fast and loose with some of its internal objects, e.g.
    // `rb_str_tmp_frozen_acquire` allocates a string with no class (klass=0).
    // Thus, we need to make sure there's actually a class before getting its name.

    if (klass != 0) {
      const char *name = rb_class2name(klass);
      size_t name_length = name != NULL ? strlen(name) : 0;

      if (name_length > 0) {
        class_name = (ddog_CharSlice) {.ptr = name, .len = name_length};
      } else {
        // @ivoanjo: I'm not sure this can ever happen, but just-in-case
        class_name = ruby_value_type_to_class_name(type);
      }
    } else {
      // Fallback for objects with no class. Objects with no class are a way for the Ruby VM to mark them
      // as internal objects; see rb_objspace_internal_object_p for details.
      class_name = ruby_value_type_to_class_name(type);
    }
  } else if (type == RUBY_T_IMEMO) {
    const char *imemo_string = imemo_kind(new_object);
    if (imemo_string != NULL) {
      snprintf(imemo_type, 100, "(VM Internal, T_IMEMO, %s)", imemo_string);
      class_name = (ddog_CharSlice) {.ptr = imemo_type, .len = strlen(imemo_type)};
    } else { // Ruby < 3
      class_name = DDOG_CHARSLICE_C("(VM Internal, T_IMEMO)");
    }
  } else {
    class_name = ruby_vm_type; // For other weird internal things we just use the VM type
  }

  bool needs_after_allocation = track_object(state->recorder_instance, new_object, sample_weight, class_name);

  VALUE current_thread = rb_thread_current();

  trigger_sample_for_thread(
    state,
    current_thread,
    thread_context,
    (sample_values) {.alloc_samples = sample_weight, .alloc_samples_unscaled = 1, .heap_sample = true},
    INVALID_TIME, // For now we're not collecting timestamps for allocation events, as per profiling team internal discussions
    &ruby_vm_type,
    &class_name,
    /* is_gvl_waiting_state: */ false,
    /* is_safe_to_allocate_objects: */ false // Not safe to allocate further inside the NEWOBJ tracepoint
  );

  return needs_after_allocation;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample_allocation(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE sample_weight, VALUE new_object) {
  per_thread_context *thread_context = get_per_thread_context(rb_thread_current());
  if (thread_context == NULL) {
    rb_raise(rb_eRuntimeError, "Missing per_thread_context for current thread in _native_sample_allocation");
  }

  debug_enter_unsafe_context();

  bool needs_after_allocation = thread_context_collector_sample_allocation(collector_instance, thread_context, NUM2UINT(sample_weight), new_object);

  debug_leave_unsafe_context();

  // We could instead choose to automatically trigger the after allocation here; yet, it seems kinda nice to keep it manual for
  // the tests so we can pull on each lever separately and observe "the sausage being made" in steps
  return needs_after_allocation ? Qtrue : Qfalse;
}

static VALUE new_empty_thread_inner(DDTRACE_UNUSED void *arg) {
  rb_thread_sleep(INT_MAX);
  return Qnil;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::ThreadContext behavior using RSpec.
// It SHOULD NOT be used for other purposes.
// (It creates an empty native thread, so we can test our native thread naming fallback)
static VALUE _native_new_empty_thread(DDTRACE_UNUSED VALUE self) {
  return rb_thread_create(new_empty_thread_inner, NULL);
}

static ddog_CharSlice ruby_value_type_to_class_name(enum ruby_value_type type) {
  switch (type) {
    case(RUBY_T_OBJECT  ): return DDOG_CHARSLICE_C("Object");
    case(RUBY_T_CLASS   ): return DDOG_CHARSLICE_C("Class");
    case(RUBY_T_MODULE  ): return DDOG_CHARSLICE_C("Module");
    case(RUBY_T_FLOAT   ): return DDOG_CHARSLICE_C("Float");
    case(RUBY_T_STRING  ): return DDOG_CHARSLICE_C("String");
    case(RUBY_T_REGEXP  ): return DDOG_CHARSLICE_C("Regexp");
    case(RUBY_T_ARRAY   ): return DDOG_CHARSLICE_C("Array");
    case(RUBY_T_HASH    ): return DDOG_CHARSLICE_C("Hash");
    case(RUBY_T_STRUCT  ): return DDOG_CHARSLICE_C("Struct");
    case(RUBY_T_BIGNUM  ): return DDOG_CHARSLICE_C("Integer");
    case(RUBY_T_FILE    ): return DDOG_CHARSLICE_C("File");
    case(RUBY_T_DATA    ): return DDOG_CHARSLICE_C("(VM Internal, T_DATA)");
    case(RUBY_T_MATCH   ): return DDOG_CHARSLICE_C("MatchData");
    case(RUBY_T_COMPLEX ): return DDOG_CHARSLICE_C("Complex");
    case(RUBY_T_RATIONAL): return DDOG_CHARSLICE_C("Rational");
    case(RUBY_T_NIL     ): return DDOG_CHARSLICE_C("NilClass");
    case(RUBY_T_TRUE    ): return DDOG_CHARSLICE_C("TrueClass");
    case(RUBY_T_FALSE   ): return DDOG_CHARSLICE_C("FalseClass");
    case(RUBY_T_SYMBOL  ): return DDOG_CHARSLICE_C("Symbol");
    case(RUBY_T_FIXNUM  ): return DDOG_CHARSLICE_C("Integer");
                  default: return DDOG_CHARSLICE_C("(VM Internal, Missing class)");
  }
}

// Used to access OpenTelemetry::Trace.const_get(:CURRENT_SPAN_KEY). Will raise exceptions if it fails.
static VALUE read_otel_current_span_key_const(DDTRACE_UNUSED VALUE _unused) {
  VALUE opentelemetry_module = rb_const_get(rb_cObject, rb_intern("OpenTelemetry"));
  ENFORCE_TYPE(opentelemetry_module, T_MODULE);
  VALUE trace_module = rb_const_get(opentelemetry_module, rb_intern("Trace"));
  ENFORCE_TYPE(trace_module, T_MODULE);
  return rb_const_get(trace_module, rb_intern("CURRENT_SPAN_KEY"));
}

static VALUE get_otel_current_span_key(thread_context_collector_state *state, bool is_safe_to_allocate_objects) {
  if (state->otel_current_span_key == Qtrue) { // Qtrue means we haven't tried to extract it yet
    if (!is_safe_to_allocate_objects) {
      // Calling read_otel_current_span_key_const below can trigger exceptions and arbitrary Ruby code running (e.g.
      // `const_missing`, etc). Not safe to call in this situation, so we just skip otel info for this sample.
      return Qnil;
    }

    // If this fails, we want to fail gracefully, rather than raise an exception (e.g. if the opentelemetry gem
    // gets refactored, we should not fall on our face)
    VALUE span_key = rb_protect(read_otel_current_span_key_const, Qnil, NULL);
    rb_set_errinfo(Qnil); // **Clear any pending exception after ignoring it**

    // Note that this gets set to Qnil if we failed to extract the correct value, and thus we won't try to extract it again
    state->otel_current_span_key = span_key;
  }

  return state->otel_current_span_key;
}

// This method gets used when ddtrace is being used indirectly via the opentelemetry APIs. Information gets stored slightly
// differently, and this codepath handles it.
static void ddtrace_otel_trace_identifiers_for(
  thread_context_collector_state *state,
  VALUE *active_trace,
  VALUE *root_span,
  VALUE *numeric_span_id,
  VALUE active_span,
  VALUE otel_values,
  bool is_safe_to_allocate_objects
) {
  VALUE resolved_numeric_span_id =
    active_span == Qnil ?
      // For traces started from otel spans, the span id will be empty, and the @parent_span_id has the right value
      rb_ivar_get(*active_trace, at_parent_span_id_id /* @parent_span_id */) :
      // Regular span created by ddtrace
      rb_ivar_get(active_span, at_id_id /* @id */);

  if (resolved_numeric_span_id == Qnil) return;

  VALUE otel_current_span_key = get_otel_current_span_key(state, is_safe_to_allocate_objects);
  if (otel_current_span_key == Qnil) return;
  VALUE current_trace = *active_trace;

  // ddtrace uses a different structure when spans are created from otel, where each otel span will have a unique ddtrace
  // trace and span representing it. Each ddtrace trace is then connected to the previous otel span, forming a linked
  // list. The local root span is going to be the trace/span we find at the end of this linked list.
  while (otel_values != Qnil) {
    VALUE otel_span = safely_lookup_hash_without_going_into_ruby_code(otel_values, otel_current_span_key);
    if (otel_span == Qnil) break;
    VALUE next_trace = rb_ivar_get(otel_span, at_datadog_trace_id);
    if (next_trace == Qnil) break;

    current_trace = next_trace;
    otel_values = rb_ivar_get(current_trace, at_otel_values_id /* @otel_values */);
  }

  // We found the last trace in the linked list. This contains the local root span
  VALUE resolved_root_span = rb_ivar_get(current_trace, at_root_span_id /* @root_span */);
  if (resolved_root_span == Qnil) return;

  *root_span = resolved_root_span;
  *active_trace = current_trace;
  *numeric_span_id = resolved_numeric_span_id;
}

void thread_context_collector_sample_skipped_allocation_samples(VALUE self_instance, unsigned int skipped_samples) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  ddog_prof_Label labels[] = {
    // Providing .num = 0 should not be needed but the tracer-2.7 docker image ships a buggy gcc that complains about this
    {.key = DDOG_CHARSLICE_C("thread id"),        .str = DDOG_CHARSLICE_C("SS"),                .num = 0},
    {.key = DDOG_CHARSLICE_C("thread name"),      .str = DDOG_CHARSLICE_C("Skipped Samples"),   .num = 0},
    {.key = DDOG_CHARSLICE_C("allocation class"), .str = DDOG_CHARSLICE_C("(Skipped Samples)"), .num = 0},
  };
  ddog_prof_Slice_Label slice_labels = {.ptr = labels, .len = sizeof(labels) / sizeof(labels[0])};

  record_placeholder_stack(
    state->recorder_instance,
    (sample_values) {.alloc_samples = skipped_samples},
    (sample_labels) {
      .labels = slice_labels,
      .state_label = NULL,
      .end_timestamp_ns = 0, // For now we're not collecting timestamps for allocation events
    },
    DDOG_CHARSLICE_C("Skipped Samples")
  );
}

static VALUE _native_sample_skipped_allocation_samples(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE skipped_samples) {
  debug_enter_unsafe_context();

  thread_context_collector_sample_skipped_allocation_samples(collector_instance, NUM2UINT(skipped_samples));

  debug_leave_unsafe_context();

  return Qtrue;
}

#ifndef NO_CURRENT_FIBER_FOR // Ruby 3.1+
  static VALUE otel_context_storage_for(thread_context_collector_state *state, VALUE thread) {
    if (state->otel_context_source == OTEL_CONTEXT_SOURCE_FIBER_IVAR) { // otel-api 1.5+
      VALUE current_fiber = current_fiber_for(thread);
      return current_fiber == Qnil ? Qnil : rb_ivar_get(current_fiber, otel_fiber_context_storage_id /* @opentelemetry_context */);
    }

    if (state->otel_context_source == OTEL_CONTEXT_SOURCE_FIBER_LOCAL) { // otel-api < 1.5
      return rb_thread_local_aref(thread, otel_context_storage_id /* __opentelemetry_context_storage__ */);
    }

    // If we got here, it means we never observed a context being set. Let's probe which one to use.
    VALUE current_fiber = current_fiber_for(thread);
    if (current_fiber != Qnil) {
      VALUE context_storage = rb_ivar_get(current_fiber, otel_fiber_context_storage_id /* @opentelemetry_context */);
      if (context_storage != Qnil) {
        state->otel_context_source = OTEL_CONTEXT_SOURCE_FIBER_IVAR; // Remember for next time
        return context_storage;
      }
    } else {
      VALUE context_storage = rb_thread_local_aref(thread, otel_context_storage_id /* __opentelemetry_context_storage__ */);
      if (context_storage != Qnil) {
        state->otel_context_source = OTEL_CONTEXT_SOURCE_FIBER_LOCAL; // Remember for next time
        return context_storage;
      }
    }

    // There's no context storage attached to the current thread
    return Qnil;
  }
#else
  static inline VALUE otel_context_storage_for(DDTRACE_UNUSED thread_context_collector_state *state, VALUE thread) {
    return rb_thread_local_aref(thread, otel_context_storage_id /* __opentelemetry_context_storage__ */);
  }
#endif

// This method differs from trace_identifiers_for/ddtrace_otel_trace_identifiers_for to support the situation where
// the opentelemetry ruby library is being used for tracing AND the ddtrace tracing bits are not involved at all.
//
// Thus, in this case, we're directly reading from the opentelemetry stuff, which is different to how ddtrace tracing
// does it.
//
// This is somewhat brittle: we're coupling on internal details of the opentelemetry gem to get what we need. In the
// future maybe the otel ruby folks would be open to having a nice public way of getting this data that suits the
// usecase of profilers.
// Until then, the strategy below is to be extremely defensive, and if anything is out of place, we immediately return
// and give up on getting trace data from opentelemetry. (Thus, worst case would be -- you upgrade opentelemetry and
// profiling features relying on reading this data stop working, but you'll still get profiles and the app will be
// otherwise undisturbed).
//
// Specifically, the way this works is:
// 1. The latest entry in the opentelemetry context storage represents the current span (if any). We take the span id
//    and trace id from this span.
// 2. To find the local root span id, we walk the context storage backwards from the current span, and find the earliest
//    entry in the context storage that has the same trace id as the current span; we use the found span as the local
//    root span id.
//    This matches the semantics of how ddtrace tracing creates a TraceOperation and assigns a local root span to it.
static void otel_without_ddtrace_trace_identifiers_for(
  thread_context_collector_state *state,
  VALUE thread,
  trace_identifiers *trace_identifiers_result,
  bool is_safe_to_allocate_objects
) {
  VALUE context_storage = otel_context_storage_for(state, thread);

  // If it exists, context_storage is expected to be an Array[OpenTelemetry::Context]
  if (context_storage == Qnil || !RB_TYPE_P(context_storage, T_ARRAY)) return;

  VALUE otel_current_span_key = get_otel_current_span_key(state, is_safe_to_allocate_objects);
  if (otel_current_span_key == Qnil) return;

  long active_context_index = RARRAY_LEN(context_storage) - 1;
  if (active_context_index < 0) return;

  otel_span active_span = otel_span_from(rb_ary_entry(context_storage, active_context_index), otel_current_span_key);
  if (active_span.span == Qnil) return;

  otel_span local_root_span = active_span;

  // Now find the oldest span starting from the active span that still has the same trace id as the active span
  for (long i = active_context_index - 1; i >= 0; i--) {
    otel_span checking_span = otel_span_from(rb_ary_entry(context_storage, i), otel_current_span_key);
    if (checking_span.span == Qnil) return;

    if (rb_str_equal(active_span.trace_id, checking_span.trace_id) == Qfalse) break;

    local_root_span = checking_span;
  }

  // Convert the span ids into uint64_t to match what the Datadog tracer does
  trace_identifiers_result->span_id = otel_span_id_to_uint(active_span.span_id);
  trace_identifiers_result->local_root_span_id = otel_span_id_to_uint(local_root_span.span_id);

  if (trace_identifiers_result->span_id == 0 || trace_identifiers_result->local_root_span_id == 0) return;

  trace_identifiers_result->valid = true;

  if (!state->endpoint_collection_enabled) return;

  VALUE root_span_type = rb_ivar_get(local_root_span.span, at_kind_id /* @kind */);
  // We filter out spans that don't have `kind: :server`
  if (root_span_type == Qnil || !RB_TYPE_P(root_span_type, T_SYMBOL) || !RB_STATIC_SYM_P(root_span_type) || SYM2ID(root_span_type) != server_id) return;

  VALUE trace_resource = rb_ivar_get(local_root_span.span, at_name_id /* @name */);
  if (!RB_TYPE_P(trace_resource, T_STRING)) return;

  trace_identifiers_result->trace_endpoint = trace_resource;
}

static otel_span otel_span_from(VALUE otel_context, VALUE otel_current_span_key) {
  otel_span failed = {.span = Qnil, .span_id = Qnil, .trace_id = Qnil};

  if (otel_context == Qnil) return failed;

  VALUE context_entries = rb_ivar_get(otel_context, at_entries_id /* @entries */);
  if (context_entries == Qnil || !RB_TYPE_P(context_entries, T_HASH)) return failed;

  // If it exists, context_entries is expected to be a Hash[OpenTelemetry::Context::Key, OpenTelemetry::Trace::Span]
  VALUE span = safely_lookup_hash_without_going_into_ruby_code(context_entries, otel_current_span_key);
  if (span == Qnil) return failed;

  // If it exists, span_context is expected to be a OpenTelemetry::Trace::SpanContext (don't confuse it with OpenTelemetry::Context)
  VALUE span_context = rb_ivar_get(span, at_context_id /* @context */);
  if (span_context == Qnil) return failed;

  VALUE span_id = rb_ivar_get(span_context, at_span_id_id /* @span_id */);
  VALUE trace_id = rb_ivar_get(span_context, at_trace_id_id /* @trace_id */);
  if (span_id == Qnil || trace_id == Qnil || !RB_TYPE_P(span_id, T_STRING) || !RB_TYPE_P(trace_id, T_STRING)) return failed;

  return (otel_span) {.span = span, .span_id = span_id, .trace_id = trace_id};
}

// Otel span ids are represented as a big-endian 8-byte string
static uint64_t otel_span_id_to_uint(VALUE otel_span_id) {
  if (!RB_TYPE_P(otel_span_id, T_STRING) || RSTRING_LEN(otel_span_id) != 8) { return 0; }

  unsigned char *span_bytes = (unsigned char*) StringValuePtr(otel_span_id);

  return \
    ((uint64_t)span_bytes[0] << 56) |
    ((uint64_t)span_bytes[1] << 48) |
    ((uint64_t)span_bytes[2] << 40) |
    ((uint64_t)span_bytes[3] << 32) |
    ((uint64_t)span_bytes[4] << 24) |
    ((uint64_t)span_bytes[5] << 16) |
    ((uint64_t)span_bytes[6] <<  8) |
    ((uint64_t)span_bytes[7]);
}

void thread_context_collector_stats(VALUE self_instance, VALUE stats_hash) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);
  stats_to_ruby_hash(state, stats_hash);
}

void thread_context_collector_stats_reset_not_thread_safe(VALUE self_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);
  state->stats = (struct stats) {};
}

static void mark_thread_as_profiler_internal(per_thread_context *ctx) {
  ctx->is_profiler_internal_thread = true;
}

void thread_context_collector_profiler_internal_thread_started(void) {
  per_thread_context *ctx = get_or_create_context_for(rb_thread_current());
  mark_thread_as_profiler_internal(ctx);
}

static VALUE _native_mark_thread_as_profiler_internal(DDTRACE_UNUSED VALUE self, VALUE thread) {
  per_thread_context *ctx = get_or_create_context_for(thread);
  mark_thread_as_profiler_internal(ctx);
  return Qnil;
}

// Called via rb_ensure when a profiler-internal thread (worker or idle helper) is about to exit.
// Records a final sample so the thread's accumulated cpu/wall time since the last on_serialize
// flush is not lost. on_serialize (below) also flushes profiler-internal threads during periodic
// serialization, but it can't help at shutdown: by the time the final serialize runs, these
// threads are already dead and absent from thread_list.
void thread_context_collector_profiler_internal_thread_done(VALUE self_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  VALUE current_thread = rb_thread_current();
  per_thread_context *thread_context = get_or_create_context_for(current_thread);
  if (!thread_context->is_profiler_internal_thread) {
    rb_raise(rb_eRuntimeError, "current thread %"PRIsVALUE" is not profiler-internal thread", current_thread);
  }

  long current_cpu_time_ns = cpu_time_now_ns(thread_context);
  long current_monotonic_wall_time_ns = monotonic_wall_time_now_ns(RAISE_ON_FAILURE);

  update_metrics_and_sample(
    state,
    current_thread,
    thread_context,
    current_cpu_time_ns,
    current_monotonic_wall_time_ns,
    true);
}

// Flushes threads whose last per-tick sample was skipped (either by the SUSPENDED-skip
// optimization, or by is_profiler_internal_thread) so their accumulated time is recorded.
// Called by the stack recorder at the start of _native_serialize (regular periodic flush).
void thread_context_collector_on_serialize(VALUE self_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  long current_monotonic_wall_time_ns = monotonic_wall_time_now_ns(RAISE_ON_FAILURE);
  VALUE threads = thread_list(state);
  const long thread_count = RARRAY_LEN(threads);

  for (long i = 0; i < thread_count; i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    per_thread_context *thread_context = get_per_thread_context(thread);

    if (thread_context != NULL && (thread_context->was_skipped_at_last_sample || thread_context->is_profiler_internal_thread)) {
      long current_cpu_time_ns = cpu_time_now_ns(thread_context);
      // We need to force_sample=true otherwise this sample would be skipped too
      update_metrics_and_sample(
        state,
        thread,
        thread_context,
        current_cpu_time_ns,
        current_monotonic_wall_time_ns,
        true);
    }
  }
}

#ifndef NO_GVL_INSTRUMENTATION
  void thread_context_collector_on_gvl_released(per_thread_context *thread_context) {
    thread_context->gvl_state_change_count |= GVL_SUSPENDED;
  }

  void thread_context_collector_on_gvl_waiting(per_thread_context *thread_context) {
    long current_monotonic_wall_time_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);
    if (current_monotonic_wall_time_ns <= 0) return;

    thread_context->gvl_waiting_at = current_monotonic_wall_time_ns;
  }

  // This function runs on the passed thread and has the GVL because it gets called just after the Ruby thread acquired the GVL
  __attribute__((warn_unused_result))
  on_gvl_running_result thread_context_collector_on_gvl_running(VALUE self_instance, VALUE thread, per_thread_context *thread_context) {
    thread_context_collector_state *state;
    TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

    // Bump the event counter and clears the state bit to "running"
    uint64_t counter_portion = thread_context->gvl_state_change_count >> 1;
    thread_context->gvl_state_change_count = ((counter_portion + 1) << 1) | GVL_RUNNING;

    long gvl_waiting_at = thread_context->gvl_waiting_at;
    // Thread was not waiting on gvl
    if (gvl_waiting_at == 0) {
      return (on_gvl_running_result) {.action = ON_GVL_RUNNING_UNKNOWN, .waiting_for_gvl_duration_ns = 0};
    }
    // @ivoanjo: I'm not sure if this can happen -- It means we should've sampled already but haven't gotten the chance yet?
    if (gvl_waiting_at < 0) {
      return (on_gvl_running_result) {.action = ON_GVL_RUNNING_SAMPLE, .waiting_for_gvl_duration_ns = 0};
    }

    long waiting_for_gvl_duration_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE) - gvl_waiting_at;

    bool should_sample = waiting_for_gvl_duration_ns >= state->waiting_for_gvl_threshold_ns;

    if (should_sample) {
      // We flip the gvl_waiting_at to negative to mark that the thread is now running and no longer waiting
      long gvl_waiting_at_is_now_running = -gvl_waiting_at;

      thread_context->gvl_waiting_at = gvl_waiting_at_is_now_running;
    } else {
      thread_context->gvl_waiting_at = 0;

      // Even though the GVL wait itself was below threshold, if the thread had skipped samples
      // (was suspended for a long time without the GVL), we still need to force a sample now.
      // Otherwise, the accumulated idle wall-time would be reported against whatever stack the
      // thread runs next, misrepresenting the time spent idle.
      if (thread_context->was_skipped_at_last_sample) {
        should_sample = true;
      }
    }

    if (should_sample) {
      // We prepare the sample here because the postponed job might be called some time later,
      // possibly after some Ruby calls which change the Ruby stack,
      // and we want to attribute the time acquiring or without the GVL to the correct Ruby stack.
      prepare_sample_thread(thread, &thread_context->sampling_buffer);
    }

    return (on_gvl_running_result) {
      .action = should_sample ? ON_GVL_RUNNING_SAMPLE : ON_GVL_RUNNING_DONT_SAMPLE,
      .waiting_for_gvl_duration_ns = waiting_for_gvl_duration_ns,
    };
  }

  // Why does this method need to exist?
  //
  // You may be surprised to see that if we never call this function (from cpu_and_wall_time_worker), Waiting for GVL
  // samples will still show up.
  // This is because regular cpu/wall-time samples also use `update_metrics_and_sample` which will do the right thing
  // and push "Waiting for GVL" samples as needed.
  //
  // The reason this method needs to exist and be called very shortly after thread_context_collector_on_gvl_running
  // returning true is to ensure accuracy of both the timing and stack for the Waiting for GVL sample.
  //
  // Timing:
  // Because we currently only record the timestamp when the Waiting for GVL started and not when the Waiting for GVL ended,
  // we rely on pushing a sample as soon as possible when the Waiting for GVL ends so that the timestamp of the sample
  // actually matches when we stopped waiting.
  //
  // Stack:
  // If the thread starts working without the end of the Waiting for GVL sample, then by the time the thread is sampled
  // via the regular cpu/wall-time samples mechanism, the stack can be inaccurate (e.g. does not correctly pinpoint
  // where the waiting happened).
  //
  // Arguably, the last sample after Waiting for GVL ended (when gvl_waiting_at < 0) should always come from this method
  // and not a regular cpu/wall-time sample BUT since all of these things are happening in parallel/concurrently I suspect
  // it's possible for a regular sample to kick in just before this one.
  //
  // ---
  //
  // Always called with the GVL, either from a postponed_job or from tests.
  //
  // NOTE: In normal use, current_thread is expected to be == rb_thread_current(); the `current_thread` parameter only
  // exists to enable testing.
  VALUE thread_context_collector_sample_after_gvl_running(VALUE self_instance, VALUE current_thread, long current_monotonic_wall_time_ns) {
    thread_context_collector_state *state;
    TypedData_Get_Struct(self_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

    per_thread_context *thread_context = get_or_create_context_for(current_thread);

    long gvl_waiting_at = thread_context->gvl_waiting_at;

    if (gvl_waiting_at >= 0 && !thread_context->was_skipped_at_last_sample) {
      // @ivoanjo: I'm not sure if this can ever happen. This means that we're not on the same thread
      // that ran `thread_context_collector_on_gvl_running` and made the decision to sample OR a regular sample was
      // triggered ahead of us.
      // We do nothing in this case.
      return Qfalse;
    }

    // We don't actually account for cpu-time during Waiting for GVL. BUT, we may choose to push an
    // extra sample to represent the period prior to Waiting for GVL. To support that, we retrieve the current
    // cpu-time of the thread and let `update_metrics_and_sample` decide what to do with it.
    long cpu_time_for_thread = cpu_time_now_ns(thread_context);

    // TODO: Should we update the dynamic sampling rate overhead tracking with this sample as well?

    update_metrics_and_sample(
      state,
      current_thread,
      thread_context,
      cpu_time_for_thread,
      current_monotonic_wall_time_ns,
      false);

    return Qtrue;
  }

  // This method is intended to be called from update_metrics_and_sample. It exists to handle extra sampling steps we
  // need to take when sampling cpu/wall-time for a thread that's in the "Waiting for GVL" state.
  __attribute__((warn_unused_result))
  static bool handle_gvl_waiting(
    thread_context_collector_state *state,
    VALUE thread_being_sampled,
    per_thread_context *thread_context,
    long current_cpu_time_ns
  ) {
    long gvl_waiting_at = thread_context->gvl_waiting_at;

    bool is_gvl_waiting_state = gvl_waiting_at != 0;

    if (!is_gvl_waiting_state) return false;

    // We can be in one of 2 situations here:
    //
    // 1. The current sample is the first one after we entered the "Waiting for GVL" state
    //    (wall_time_at_previous_sample_ns < abs(gvl_waiting_at))
    //
    //                             time ─────►
    //  ...──────────────┬───────────────────...
    //       Other state │ Waiting for GVL
    //  ...──────────────┴───────────────────...
    //     ▲                               ▲
    //     └─ Previous sample              └─ Regular sample (caller)
    //
    //   In this case, we'll want to push two samples: a) one for the current time (handled by the caller), b) an extra sample
    //   to represent the remaining cpu/wall time before the "Waiting for GVL" started (for timeline purposes):
    //
    //                             time ─────►
    //  ...──────────────┬───────────────────...
    //       Other state │ Waiting for GVL
    //  ...──────────────┴───────────────────...
    //     ▲             ▲                 ▲
    //     └─ Prev...    └─ Extra sample   └─ Regular sample (caller)
    //
    // 2. The current sample is the n-th one after we entered the "Waiting for GVL" state
    //    (wall_time_at_previous_sample_ns > abs(gvl_waiting_at))
    //
    //                             time ─────►
    //  ...──────────────┬───────────────────────────────────────────────...
    //       Other state │ Waiting for GVL
    //  ...──────────────┴───────────────────────────────────────────────...
    //     ▲                               ▲                          ▲
    //     └─ Previous sample              └─ Previous sample         └─ Regular sample (caller)
    //
    //   In this case, we just report back to the caller that the thread is in the "Waiting for GVL" state.
    //
    // ---
    //
    // Overall, gvl_waiting_at will be > 0 if still in the "Waiting for GVL" state and < 0 if we actually reached the end of
    // the wait.
    //
    // It doesn't really matter if the thread is still waiting or just reached the end of the wait: each sample represents
    // a snapshot at time ending now, so if the state finished, it just means the next sample will be a regular one.

    if (gvl_waiting_at < 0) {
      // Negative means the waiting for GVL just ended, so we clear the state, so next samples no longer represent waiting
      thread_context->gvl_waiting_at = 0;
    }

    long gvl_waiting_started_wall_time_ns = labs(gvl_waiting_at);

    if (thread_context->wall_time_at_previous_sample_ns < gvl_waiting_started_wall_time_ns) { // situation 1 above
      long cpu_time_elapsed_ns = update_time_since_previous_sample(
        &thread_context->cpu_time_at_previous_sample_ns,
        current_cpu_time_ns,
        thread_context->gc_tracking.cpu_time_at_start_ns,
        IS_CPU_TIME
      );

      long duration_until_start_of_gvl_waiting_ns = update_time_since_previous_sample(
        &thread_context->wall_time_at_previous_sample_ns,
        gvl_waiting_started_wall_time_ns,
        INVALID_TIME,
        IS_WALL_TIME
      );

      // Push extra sample
      trigger_sample_for_thread(
        state,
        thread_being_sampled,
        thread_context,
        (sample_values) {.cpu_time_ns = cpu_time_elapsed_ns, .cpu_or_wall_samples = 1, .wall_time_ns = duration_until_start_of_gvl_waiting_ns},
        gvl_waiting_started_wall_time_ns,
        NULL,
        NULL,
        /* is_gvl_waiting_state: */ false, // This is the extra sample before the wait begun; only the next sample will be in the gvl waiting state
        /* is_safe_to_allocate_objects: */ true // This is similar to a regular cpu/wall sample, so it's also safe
      );
    }

    return true;
  }

  static VALUE _native_on_gvl_waiting(DDTRACE_UNUSED VALUE self, VALUE thread) {
    ENFORCE_THREAD(thread);

    debug_enter_unsafe_context();

    per_thread_context *thread_context = get_per_thread_context(thread);
    if (thread_context) thread_context_collector_on_gvl_waiting(thread_context);

    debug_leave_unsafe_context();

    return Qnil;
  }

  static VALUE _native_gvl_waiting_at_for(DDTRACE_UNUSED VALUE self, VALUE thread) {
    ENFORCE_THREAD(thread);

    debug_enter_unsafe_context();

    per_thread_context *thread_context = get_per_thread_context(thread);
    VALUE result = thread_context ? LONG2NUM(thread_context->gvl_waiting_at) : Qnil;

    debug_leave_unsafe_context();

    return result;
  }

  static VALUE _native_on_gvl_running(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE thread) {
    ENFORCE_THREAD(thread);

    debug_enter_unsafe_context();

    per_thread_context *thread_context = get_per_thread_context(thread);
    VALUE result;
    if (thread_context) {
      result = thread_context_collector_on_gvl_running(collector_instance, thread, thread_context).action == ON_GVL_RUNNING_SAMPLE ? Qtrue : Qfalse;
    } else {
      result = Qfalse;
    }

    debug_leave_unsafe_context();

    return result;
  }

  static VALUE _native_on_gvl_released(DDTRACE_UNUSED VALUE self, VALUE thread) {
    ENFORCE_THREAD(thread);

    debug_enter_unsafe_context();

    per_thread_context *thread_context = get_per_thread_context(thread);
    if (thread_context) thread_context_collector_on_gvl_released(thread_context);

    debug_leave_unsafe_context();

    return Qnil;
  }

  static VALUE _native_sample_after_gvl_running(DDTRACE_UNUSED VALUE self, VALUE collector_instance, VALUE thread, VALUE allow_exception) {
    ENFORCE_THREAD(thread);
    ENFORCE_BOOLEAN(allow_exception);

    if (allow_exception == Qfalse) debug_enter_unsafe_context();

    VALUE result = thread_context_collector_sample_after_gvl_running(
      collector_instance,
      thread,
      monotonic_wall_time_now_ns(RAISE_ON_FAILURE)
    );

    if (allow_exception == Qfalse) debug_leave_unsafe_context();

    return result;
  }

#else
  static bool handle_gvl_waiting(
    DDTRACE_UNUSED thread_context_collector_state *state,
    DDTRACE_UNUSED VALUE thread_being_sampled,
    DDTRACE_UNUSED per_thread_context *thread_context,
    DDTRACE_UNUSED long current_cpu_time_ns
  ) { return false; }

#endif // NO_GVL_INSTRUMENTATION

static VALUE _native_apply_delta_to_cpu_time_at_previous_sample_ns(DDTRACE_UNUSED VALUE self, VALUE thread, VALUE delta_ns) {
  ENFORCE_THREAD(thread);

  per_thread_context *thread_context = get_per_thread_context(thread);
  if (thread_context == NULL) raise_error(rb_eArgError, "Unexpected: This method cannot be used unless the per-thread context for the thread already exists");

  thread_context->cpu_time_at_previous_sample_ns += NUM2LONG(delta_ns);

  return Qtrue;
}

#define MAX_SAFE_LOOKUP_SIZE 16

typedef struct { VALUE lookup_key; VALUE result; } safe_lookup_hash_state;

static int safe_lookup_hash_iterate(VALUE key, VALUE value, VALUE state_ptr) {
  safe_lookup_hash_state *state = (safe_lookup_hash_state *) state_ptr;

  if (key == state->lookup_key) {
    state->result = value;
    return ST_STOP;
  }

  return ST_CONTINUE;
}

// This method exists because we need to look up a hash during sampling, but we don't want to invoke any
// Ruby code as a side effect. To be able to look up by hash, `rb_hash_lookup` calls `#hash` on the key,
// which we want to avoid.
// Thus, instead, we opt to just iterate through the hash and check if we can find what we're looking for.
//
// To avoid having too much overhead here we only iterate in hashes up to MAX_SAFE_LOOKUP_SIZE.
// Note that we don't even try to iterate if the hash is bigger -- this is to avoid flaky behavior where
// depending on the internal storage order of the hash we may or not find the key, and instead we always
// enforce the size.
static VALUE safely_lookup_hash_without_going_into_ruby_code(VALUE hash, VALUE key) {
  if (!RB_TYPE_P(hash, T_HASH) || RHASH_SIZE(hash) > MAX_SAFE_LOOKUP_SIZE) return Qnil;

  safe_lookup_hash_state state = {.lookup_key = key, .result = Qnil};

  rb_hash_foreach(hash, safe_lookup_hash_iterate, (VALUE) &state);

  return state.result;
}

static VALUE _native_system_epoch_time_now_ns(DDTRACE_UNUSED VALUE self, VALUE collector_instance) {
  thread_context_collector_state *state;
  TypedData_Get_Struct(collector_instance, thread_context_collector_state, &thread_context_collector_typed_data, state);

  long current_monotonic_wall_time_ns = monotonic_wall_time_now_ns(RAISE_ON_FAILURE);
  long system_epoch_time_ns = monotonic_to_system_epoch_ns(&state->time_converter_state, current_monotonic_wall_time_ns);

  return LONG2NUM(system_epoch_time_ns);
}

static VALUE _native_prepare_sample_inside_signal_handler(DDTRACE_UNUSED VALUE self) {
  return thread_context_collector_prepare_sample_inside_signal_handler() ? Qtrue : Qfalse;
}
