#include <ruby.h>

// Used to periodically (time-based) sample threads, recording elapsed CPU-time and Wall-time between samples.
// This file implements the native bits of the Datadog::Profiling::Collectors::CpuAndWallTime class

static VALUE collectors_cpu_and_wall_time_class = Qnil;

struct cpu_and_wall_time_collector_state {
  VALUE recorder_instance;
};

static void cpu_and_wall_time_collector_typed_data_mark(void *state_ptr);
static void cpu_and_wall_time_collector_typed_data_free(void *state_ptr);
static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(VALUE self, VALUE recorder_instance);

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

  rb_define_method(collectors_cpu_and_wall_time_class, "initialize", _native_initialize, 1);
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

  rb_gc_mark(state->recorder_instance);
}

static void cpu_and_wall_time_collector_typed_data_free(void *state_ptr) {
  struct cpu_and_wall_time_collector_state *state = (struct cpu_and_wall_time_collector_state *) state_ptr;

  xfree(state);
}

static VALUE _native_new(VALUE klass) {
  struct cpu_and_wall_time_collector_state *state = xcalloc(1, sizeof(struct cpu_and_wall_time_collector_state));

  if (state == NULL) {
    rb_raise(rb_eNoMemError, "Failed to allocate memory for components of Datadog::Profiling::Collectors::CpuAndWallTime");
  }

  state->recorder_instance = Qnil;

  return TypedData_Wrap_Struct(collectors_cpu_and_wall_time_class, &cpu_and_wall_time_collector_typed_data, state);
}

static VALUE _native_initialize(VALUE self, VALUE recorder_instance) {
  // Quick sanity check. If the object passed here is not actually a Datadog::Profiling::StackRecorder, then
  // we will later flag that when trying to access its data using TypedData_Get_Struct.
  Check_Type(recorder_instance, T_DATA);

  struct cpu_and_wall_time_collector_state *state;
  TypedData_Get_Struct(self, struct cpu_and_wall_time_collector_state, &cpu_and_wall_time_collector_typed_data, state);

  state->recorder_instance = recorder_instance;

  return self;
}
