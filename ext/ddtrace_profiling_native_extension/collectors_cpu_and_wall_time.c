#include <ruby.h>
#include "collectors_stack.h"
#include "stack_recorder.h"
#include "private_vm_api_access.h"

// Used to periodically (time-based) sample threads, recording elapsed CPU-time and Wall-time between samples.
// This file implements the native bits of the Datadog::Profiling::Collectors::CpuAndWallTime class

static VALUE collectors_cpu_and_wall_time_class = Qnil;

struct cpu_and_wall_time_collector_state {
  // Note: Places in this file that usually need to be changed when this struct is changed are tagged with
  // "Update this when modifying state struct"
  sampling_buffer *sampling_buffer;
  VALUE recorder_instance;
};

static void cpu_and_wall_time_collector_typed_data_mark(void *state_ptr);
static void cpu_and_wall_time_collector_typed_data_free(void *state_ptr);
static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(VALUE self, VALUE collector_instance, VALUE recorder_instance, VALUE max_frames);
static VALUE _native_sample(VALUE self, VALUE collector_instance);
static void sample(VALUE collector_instance);

void collectors_cpu_and_wall_time_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  collectors_cpu_and_wall_time_class = rb_define_class_under(collectors_module, "CpuAndWallTime", rb_cObject);

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
}

// This structure is used to define a Ruby object that stores a pointer to a struct cpu_and_wall_time_collector_state
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t cpu_and_wall_time_collector_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Collectors::CpuAndWallTime",
  .function = {
    .dmark = cpu_and_wall_time_collector_typed_data_mark,
    .dfree = cpu_and_wall_time_collector_typed_data_free,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    .dcompact = NULL, // FIXME: Add support for compaction
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static void cpu_and_wall_time_collector_typed_data_mark(void *state_ptr) {
  struct cpu_and_wall_time_collector_state *state = (struct cpu_and_wall_time_collector_state *) state_ptr;

  // Update this when modifying state struct
  rb_gc_mark(state->recorder_instance);
}

static void cpu_and_wall_time_collector_typed_data_free(void *state_ptr) {
  struct cpu_and_wall_time_collector_state *state = (struct cpu_and_wall_time_collector_state *) state_ptr;

  // Update this when modifying state struct

  // Important: Remember that we're only guaranteed to see here what's been set in _native_new, aka
  // pointers that have been set NULL there may still be NULL here.
  if (state->sampling_buffer != NULL) sampling_buffer_free(state->sampling_buffer);

  xfree(state);
}

static VALUE _native_new(VALUE klass) {
  struct cpu_and_wall_time_collector_state *state = xcalloc(1, sizeof(struct cpu_and_wall_time_collector_state));

  if (state == NULL) {
    rb_raise(rb_eNoMemError, "Failed to allocate memory for components of Datadog::Profiling::Collectors::CpuAndWallTime");
  }

  // Update this when modifying state struct
  state->sampling_buffer = NULL;
  state->recorder_instance = Qnil;

  return TypedData_Wrap_Struct(collectors_cpu_and_wall_time_class, &cpu_and_wall_time_collector_typed_data, state);
}

static VALUE _native_initialize(VALUE self, VALUE collector_instance, VALUE recorder_instance, VALUE max_frames) {
  enforce_recorder_instance(recorder_instance);

  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  int max_frames_requested = NUM2INT(max_frames);
  if (max_frames_requested < 0) rb_raise(rb_eArgError, "Invalid max_frames: value must not be negative");

  // Update this when modifying state struct
  state->sampling_buffer = sampling_buffer_new(max_frames_requested);
  state->recorder_instance = recorder_instance;

  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_sample(VALUE self, VALUE collector_instance) {
  sample(collector_instance);
  return Qtrue;
}

static void sample(VALUE collector_instance) {
  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(collector_instance, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  // FIXME: How to access thread list?
  VALUE threads = rb_ary_new(); //rb_thread_list();

  const int thread_count = RARRAY_LEN(threads);
  for (int i = 0; i < thread_count; i++) {
    VALUE thread = RARRAY_AREF(threads, i);

    int64_t metric_values[ENABLED_VALUE_TYPES_COUNT] = {0};

    metric_values[CPU_TIME_VALUE_POS] = 12;
    metric_values[CPU_SAMPLES_VALUE_POS] = 34;
    metric_values[WALL_TIME_VALUE_POS] = 56;

    sample_thread(
      thread,
      state->sampling_buffer,
      state->recorder_instance,
      (ddprof_ffi_Slice_i64) {.ptr = metric_values, .len = ENABLED_VALUE_TYPES_COUNT},
      (ddprof_ffi_Slice_label) {.ptr = NULL, .len = 0} // FIXME
    );
  }
}
