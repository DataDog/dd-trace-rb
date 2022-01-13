#include <ruby.h>
#include <ruby/debug.h>

#include "clock_id.h"
#include <ddprof/ffi.h>

static VALUE native_working_p(VALUE self);
static VALUE start_allocation_tracing(VALUE self);
static void on_newobj_event(VALUE tracepoint_info, void *_unused);
static VALUE get_allocation_count(VALUE self);
static VALUE allocate_many_objects(VALUE self, VALUE how_many);
static void record_sample(int stack_depth, VALUE *stack_buffer, int *lines_buffer);
static void initialize_allocation_profile();
static VALUE ensure_string(VALUE object);
static VALUE export_allocation_profile(VALUE self);

static unsigned long allocation_count = 0;
static ddprof_ffi_Profile *allocation_profile = 0;


void Init_ddtrace_profiling_native_extension(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");
  VALUE native_extension_module = rb_define_module_under(profiling_module, "NativeExtension");

  rb_define_singleton_method(native_extension_module, "native_working?", native_working_p, 0);
  rb_funcall(native_extension_module, rb_intern("private_class_method"), 1, ID2SYM(rb_intern("native_working?")));

  rb_define_singleton_method(native_extension_module, "clock_id_for", clock_id_for, 1); // from clock_id.h

  // Experimental support for allocation tracking
  rb_define_singleton_method(native_extension_module, "start_allocation_tracing", start_allocation_tracing, 0);
  rb_define_singleton_method(native_extension_module, "allocation_count", get_allocation_count, 0);
  rb_define_singleton_method(native_extension_module, "export_allocation_profile", export_allocation_profile, 0);

  initialize_allocation_profile();
}

static VALUE native_working_p(VALUE self) {
  self_test_clock_id();

  return Qtrue;
}

static VALUE start_allocation_tracing(VALUE self) {
  VALUE tracepoint = rb_tracepoint_new(
    0, // all threads
    RUBY_INTERNAL_EVENT_NEWOBJ, // object allocation,
    on_newobj_event,
    0 // unused
  );

  return tracepoint;
}

static void on_newobj_event(VALUE tracepoint_info, void *_unused) {
  allocation_count++;

  int buffer_max_size = 1024;
  VALUE stack_buffer[buffer_max_size];
  int lines_buffer[buffer_max_size];

  int stack_depth = rb_profile_frames(
    0, // stack starting depth
    buffer_max_size,
    stack_buffer,
    lines_buffer
  );

  record_sample(stack_depth, stack_buffer, lines_buffer);

  return;
}

static VALUE get_allocation_count(VALUE self) {
  return ULONG2NUM(allocation_count);
}

static void record_sample(int stack_depth, VALUE *stack_buffer, int *lines_buffer) {
  struct ddprof_ffi_Location locations[stack_depth];
  struct ddprof_ffi_Line lines[stack_depth];

  for (int i = 0; i < stack_depth; i++) {
    VALUE name = rb_profile_frame_full_label(stack_buffer[i]);
    VALUE filename = rb_profile_frame_absolute_path(stack_buffer[i]);
    if (NIL_P(filename)) {
      filename = rb_profile_frame_path(stack_buffer[i]);
    }

    name = ensure_string(name);
    filename = ensure_string(filename);

    locations[i] = (struct ddprof_ffi_Location){.lines = (struct ddprof_ffi_Slice_line){&lines[i], 1}};
    lines[i] = (struct ddprof_ffi_Line){
      .function = (struct ddprof_ffi_Function){
        .name = {StringValuePtr(name), RSTRING_LEN(name)},
        .filename = {StringValuePtr(filename), RSTRING_LEN(filename)}
      },
      .line = lines_buffer[i],
    };
  }

  int64_t metric = 1;

  struct ddprof_ffi_Sample sample = {
    .locations = {locations, stack_depth},
    .values = {&metric, 1}
  };

  ddprof_ffi_Profile_add(allocation_profile, sample);
}

static void initialize_allocation_profile() {
  const struct ddprof_ffi_ValueType alloc_samples = {
    .type_ = {"alloc-samples", sizeof("alloc-samples") - 1},
    .unit = {"count", sizeof("count") - 1},
  };
  const struct ddprof_ffi_Slice_value_type sample_types = {&alloc_samples, 1};
  const struct ddprof_ffi_Period period = {alloc_samples, 60};
  allocation_profile = ddprof_ffi_Profile_new(sample_types, &period);
}

static VALUE ensure_string(VALUE object) {
  Check_Type(object, T_STRING);

  return object;
}

static VALUE export_allocation_profile(VALUE self) {
  struct ddprof_ffi_EncodedProfile *profile =
    ddprof_ffi_Profile_serialize(allocation_profile);

  if (profile == NULL) {
    return Qnil;
  }

  VALUE profile_string = rb_str_new((char *) profile->buffer.ptr, profile->buffer.len);

  ddprof_ffi_EncodedProfile_delete(profile);

  return profile_string;
}
