#include <ruby.h>

#include "clock_id.h"

// Each class/module here is implemented in their separate file
void collectors_cpu_and_wall_time_init(VALUE profiling_module);
void collectors_stack_init(VALUE profiling_module);
void http_transport_init(VALUE profiling_module);
void stack_recorder_init(VALUE profiling_module);

static VALUE native_working_p(VALUE self);

#define DDTRACE_EXPORT __attribute__ ((visibility ("default")))

void DDTRACE_EXPORT Init_ddtrace_profiling_native_extension(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");
  VALUE native_extension_module = rb_define_module_under(profiling_module, "NativeExtension");

  rb_define_singleton_method(native_extension_module, "native_working?", native_working_p, 0);
  rb_funcall(native_extension_module, rb_intern("private_class_method"), 1, ID2SYM(rb_intern("native_working?")));

  rb_define_singleton_method(native_extension_module, "clock_id_for", clock_id_for, 1); // from clock_id.h

  collectors_cpu_and_wall_time_init(profiling_module);
  collectors_stack_init(profiling_module);
  http_transport_init(profiling_module);
  stack_recorder_init(profiling_module);
}

static VALUE native_working_p(VALUE self) {
  self_test_clock_id();

  return Qtrue;
}
