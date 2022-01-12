#include <ruby.h>
#include <ruby/debug.h>

#include "clock_id.h"

static VALUE native_working_p(VALUE self);
static VALUE start_allocation_tracing(VALUE self);
static void on_newobj_event(VALUE tracepoint_info, void *_unused);
static VALUE get_allocation_count(VALUE self);
static VALUE allocate_many_objects(VALUE self, VALUE how_many);

static unsigned long allocation_count = 0;

void Init_ddtrace_profiling_native_extension(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");
  VALUE native_extension_module = rb_define_module_under(profiling_module, "NativeExtension");

  rb_define_singleton_method(native_extension_module, "native_working?", native_working_p, 0);
  rb_funcall(native_extension_module, rb_intern("private_class_method"), 1, ID2SYM(rb_intern("native_working?")));

  rb_define_singleton_method(native_extension_module, "clock_id_for", clock_id_for, 1); // from clock_id.h

  rb_define_singleton_method(native_extension_module, "start_allocation_tracing", start_allocation_tracing, 0);

  rb_define_singleton_method(native_extension_module, "allocation_count", get_allocation_count, 0);
  rb_define_singleton_method(native_extension_module, "allocate_many_objects", allocate_many_objects, 1);
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
  return;
}

static VALUE get_allocation_count(VALUE self) {
  return ULONG2NUM(allocation_count);
}

static VALUE allocate_many_objects(VALUE self, VALUE how_many) {
  int count = NUM2ULONG(how_many);
  for (int i = 0; i < count; i++) {
    rb_newobj();
  }

  return Qtrue;
}
