#include <ruby.h>
#include "helpers.h"
#include "collectors_stack.h"
#include "libddprof_helpers.h"
#include "private_vm_api_access.h"
#include "stack_recorder.h"

// Used to periodically (time-based) sample threads, recording elapsed CPU-time and Wall-time between samples.
// This file implements the native bits of the Datadog::Profiling::Collectors::CpuAndWallTime class

#define INVALID_TIME -1

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
  // Track how many samples we've taken.
  unsigned int sample_count;
};

// Tracks per-thread state
struct per_thread_context {
  long thread_id;
  long wall_time_at_previous_sample_ns; // Can be INVALID_TIME until initialized
};

static void cpu_and_wall_time_collector_typed_data_mark(void *state_ptr);
static void cpu_and_wall_time_collector_typed_data_free(void *state_ptr);
static int hash_map_per_thread_context_mark(st_data_t key_thread, st_data_t _value, st_data_t _argument);
static int hash_map_per_thread_context_free_values(st_data_t _thread, st_data_t value_per_thread_context, st_data_t _argument);
static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(VALUE self, VALUE collector_instance, VALUE recorder_instance, VALUE max_frames);
static VALUE _native_sample(VALUE self, VALUE collector_instance);
static void sample(VALUE collector_instance);
static VALUE _native_thread_list(VALUE self);
static struct per_thread_context *get_or_create_context_for(VALUE thread, struct cpu_and_wall_time_collector_state *state);
static void initialize_context(VALUE thread, struct per_thread_context *thread_context);
static VALUE _native_inspect(VALUE self, VALUE collector_instance);
static VALUE per_thread_context_st_table_as_ruby_hash(struct cpu_and_wall_time_collector_state *state);
static int per_thread_context_as_ruby_hash(st_data_t key_thread, st_data_t value_context, st_data_t result_hash);
static void remove_context_for_dead_threads(struct cpu_and_wall_time_collector_state *state);
static int remove_if_dead_thread(st_data_t key_thread, st_data_t value_context, st_data_t _argument);
static VALUE _native_per_thread_context(VALUE self, VALUE collector_instance);
static long update_time_since_previous_sample(long *time_at_previous_sample_ns, long current_time_ns);
static long wall_time_now_ns(struct cpu_and_wall_time_collector_state *state);
static long thread_id_for(VALUE thread);

void collectors_cpu_and_wall_time_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_cpu_and_wall_time_class = rb_define_class_under(collectors_module, "CpuAndWallTime", rb_cObject);

  // Instances of the CpuAndWallTime class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the cpu_and_wall_time_collector_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(collectors_cpu_and_wall_time_class, _native_new);

  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_initialize", _native_initialize, 3);
  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_sample", _native_sample, 1);
  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_thread_list", _native_thread_list, 0);
  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_inspect", _native_inspect, 1);
  rb_define_singleton_method(collectors_cpu_and_wall_time_class, "_native_per_thread_context", _native_per_thread_context, 1);
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
  state->sample_count = 0;

  return TypedData_Wrap_Struct(klass, &cpu_and_wall_time_collector_typed_data, state);
}

static VALUE _native_initialize(DDTRACE_UNUSED VALUE _self, VALUE collector_instance, VALUE recorder_instance, VALUE max_frames) {
  enforce_recorder_instance(recorder_instance);

  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  int max_frames_requested = NUM2INT(max_frames);
  if (max_frames_requested < 0) rb_raise(rb_eArgError, "Invalid max_frames: value must not be negative");

  // Update this when modifying state struct
  state->sampling_buffer = sampling_buffer_new(max_frames_requested);
  // hash_map_per_thread_context is already initialized, nothing to do here
  state->recorder_instance = recorder_instance;

  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  sample(collector_instance);
  return Qtrue;
}

static void sample(VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  VALUE threads = ddtrace_thread_list();
  long current_wall_time_ns = wall_time_now_ns(state);

  const long thread_count = RARRAY_LEN(threads);
  for (long i = 0; i < thread_count; i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    struct per_thread_context *thread_context = get_or_create_context_for(thread, state);

    long wall_time_elapsed_ns =
      update_time_since_previous_sample(&thread_context->wall_time_at_previous_sample_ns, current_wall_time_ns);

    int64_t metric_values[ENABLED_VALUE_TYPES_COUNT] = {0};

    // FIXME: TODO These are just dummy values for now
    metric_values[CPU_TIME_VALUE_POS] = 12; // FIXME: Placeholder until actually implemented/tested
    metric_values[CPU_SAMPLES_VALUE_POS] = 34; // FIXME: Placeholder until actually implemented/tested

    metric_values[WALL_TIME_VALUE_POS] = wall_time_elapsed_ns;

    VALUE thread_name = thread_name_for(thread);
    bool have_thread_name = thread_name != Qnil;

    int label_count = 1 + (have_thread_name ? 1 : 0);
    ddprof_ffi_Label labels[label_count];

    labels[0] = (ddprof_ffi_Label) {.key = DDPROF_FFI_CHARSLICE_C("thread id"), .num = thread_context->thread_id};
    if (have_thread_name) {
      labels[1] = (ddprof_ffi_Label) {
        .key = DDPROF_FFI_CHARSLICE_C("thread name"),
        .str = char_slice_from_ruby_string(thread_name)
      };
    }

    sample_thread(
      thread,
      state->sampling_buffer,
      state->recorder_instance,
      (ddprof_ffi_Slice_i64) {.ptr = metric_values, .len = ENABLED_VALUE_TYPES_COUNT},
      (ddprof_ffi_Slice_label) {.ptr = labels, .len = label_count}
    );
  }

  state->sample_count++;

  // TODO: This seems somewhat overkill and inefficient to do often; right now we just doing every few samples
  // but there's probably a better way to do this if we actually track when threads finish
  if (state->sample_count % 100 == 0) remove_context_for_dead_threads(state);
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_thread_list(DDTRACE_UNUSED VALUE _self) {
  return ddtrace_thread_list();
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

static void initialize_context(VALUE thread, struct per_thread_context *thread_context) {
  thread_context->thread_id = thread_id_for(thread);

  // These will get initialized during actual sampling
  thread_context->wall_time_at_previous_sample_ns = INVALID_TIME;
}

static VALUE _native_inspect(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  VALUE result = rb_str_new2(" (native state)");

  // Update this when modifying state struct
  rb_str_concat(result, rb_sprintf(" hash_map_per_thread_context=%"PRIsVALUE, per_thread_context_st_table_as_ruby_hash(state)));
  rb_str_concat(result, rb_sprintf(" recorder_instance=%"PRIsVALUE, state->recorder_instance));
  rb_str_concat(result, rb_sprintf(" sample_count=%u", state->sample_count));

  return result;
}

static VALUE per_thread_context_st_table_as_ruby_hash(struct cpu_and_wall_time_collector_state *state) {
  VALUE result = rb_hash_new();
  st_foreach(state->hash_map_per_thread_context, per_thread_context_as_ruby_hash, result);
  return result;
}

#define VALUE_COUNT(array) (sizeof(array) / sizeof(VALUE))

static int per_thread_context_as_ruby_hash(st_data_t key_thread, st_data_t value_context, st_data_t result_hash) {
  VALUE thread = (VALUE) key_thread;
  struct per_thread_context *thread_context = (struct per_thread_context*) value_context;
  VALUE result = (VALUE) result_hash;
  VALUE context_as_hash = rb_hash_new();
  rb_hash_aset(result, thread, context_as_hash);

  VALUE arguments[] = {
    ID2SYM(rb_intern("thread_id")),  /* => */ LONG2NUM(thread_context->thread_id),
    ID2SYM(rb_intern("wall_time_at_previous_sample_ns")), /* => */ LONG2NUM(thread_context->wall_time_at_previous_sample_ns)
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(context_as_hash, arguments[i], arguments[i+1]);

  return ST_CONTINUE;
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

// Returns the whole contents of the per_thread_context structs being tracked, for debugging/testing
static VALUE _native_per_thread_context(DDTRACE_UNUSED VALUE _self, VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  return per_thread_context_st_table_as_ruby_hash(state);
}

static long update_time_since_previous_sample(long *time_at_previous_sample_ns, long current_time_ns) {
  // If we didn't have a time for the previous sample, we use the current one
  if (*time_at_previous_sample_ns == INVALID_TIME) *time_at_previous_sample_ns = current_time_ns;

  long elapsed_time_ns = current_time_ns - *time_at_previous_sample_ns;
  *time_at_previous_sample_ns = current_time_ns;

  return elapsed_time_ns >= 0 ? elapsed_time_ns : 0 /* In case something really weird happened */;
}

static long wall_time_now_ns(struct cpu_and_wall_time_collector_state *state) {
  struct timespec current_monotonic;

  if (clock_gettime(CLOCK_MONOTONIC, &current_monotonic) != 0) rb_sys_fail("Failed to read CLOCK_MONOTONIC");

  return current_monotonic.tv_nsec + (current_monotonic.tv_sec * 1000 * 1000 * 1000);
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
