#include <ruby.h>
#include <ruby/debug.h>
#include "extconf.h"

#include "datadog_ruby_common.h"
#include "filters.h"
#include "collector.h"

static VALUE _native_start(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_stop(DDTRACE_UNUSED VALUE _self);
static VALUE _generate_span_event(DDTRACE_UNUSED VALUE _self, VALUE exception);
static void tracepoint_callback(VALUE self, void* tp);
static void errortracker_init(VALUE errortracking_module);

void DDTRACE_EXPORT Init_errortracker() {
    VALUE datadog_module = rb_define_module("Datadog");
    VALUE errortracking_module = rb_define_module_under(datadog_module, "Errortracking");

    collector_init(errortracking_module);
    errortracker_init(errortracking_module);
}

void errortracker_init(VALUE errortracking_module) {
    VALUE errortracker_class = rb_define_class_under(errortracking_module, "Component", rb_cObject);

    rb_define_singleton_method(errortracker_class, "_native_start", _native_start, -1);
    rb_define_singleton_method(errortracker_class, "_native_stop", _native_stop, 0);

    rb_define_attr(errortracker_class, "tracepoint", 1, 1);
    rb_define_attr(errortracker_class, "tracer", 1, 1);
}

static VALUE _native_start(int argc, VALUE* argv, VALUE self){
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE tracer = rb_hash_fetch(options, ID2SYM(rb_intern("tracer")));
  VALUE to_instrument = rb_hash_fetch(options, ID2SYM(rb_intern("to_instrument")));
  VALUE to_instrument_modules = rb_hash_fetch(options, ID2SYM(rb_intern("to_instrument_modules")));

  ENFORCE_TYPE(tracer, T_OBJECT);
  ENFORCE_TYPE(to_instrument, T_STRING);
  ENFORCE_TYPE(to_instrument_modules, T_STRING);

  VALUE collector = rb_class_new_instance(0, NULL, rb_path2class("Datadog::Core::ErrorTracking::Collector"));
  rb_iv_set(self, "@collector", collector);
  rb_iv_set(self, "@tracer", tracer);

  VALUE filter_function = generate_filter(self, to_instrument);
  rb_iv_set(self, "@filter_function", filter_function);
  double ruby_version = RFLOAT_VALUE(rb_const_get(rb_cObject, rb_intern("RUBY_VERSION")));
  VALUE tracepoint;
  if (ruby_version >= 3.3) {
    tracepoint = rb_tracepoint_new(Qnil, RUBY_EVENT_RESCUE, tracepoint_callback, (void*)self);
  } else {
    tracepoint = rb_tracepoint_new(Qnil, RUBY_EVENT_RAISE, tracepoint_callback, (void*)self);
  }
  rb_iv_set(self, "@tracepoint", tracepoint);
  rb_tracepoint_enable(tracepoint);

  return Qnil;
}

static VALUE _native_stop(VALUE self) {
  VALUE tracepoint = rb_iv_get(self, "@tracepoint");
  rb_tracepoint_disable(tracepoint);

  return Qnil;
}


static VALUE _generate_span_event(DDTRACE_UNUSED VALUE _self, VALUE exception) {
    VALUE core_module = rb_const_get(rb_cObject, rb_intern("Core"));
    VALUE error_class = rb_const_get(core_module, rb_intern("Error"));
    ID build_from_id = rb_intern("build_from");
    VALUE formatted_exception = rb_funcallv(error_class, build_from_id, 1, &exception);

    VALUE tracing_module = rb_const_get(rb_cObject, rb_intern("Tracing"));
    VALUE span_event_class = rb_const_get(tracing_module, rb_intern("SpanEvent"));

    VALUE type_sym = ID2SYM(rb_intern("type"));
    VALUE message_sym = ID2SYM(rb_intern("message"));
    VALUE stacktrace_sym = ID2SYM(rb_intern("stacktrace"));

    VALUE type = rb_funcall(formatted_exception, rb_intern("type"), 0);
    VALUE message = rb_funcall(formatted_exception, rb_intern("message"), 0);
    VALUE stacktrace = rb_funcall(formatted_exception, rb_intern("backtrace"), 0);

    VALUE attributes = rb_hash_new();
    rb_hash_aset(attributes, type_sym, type);
    rb_hash_aset(attributes, message_sym, message);
    rb_hash_aset(attributes, stacktrace_sym, stacktrace);

    VALUE name = rb_str_new_cstr("error");
    VALUE args[2] = {name, rb_hash_new()};
    rb_hash_aset(args[1], ID2SYM(rb_intern("attributes")), attributes);

    return rb_funcallv(span_event_class, rb_intern("new"), 2, args);
}

static void tracepoint_callback(VALUE tp, void* data) {
  VALUE self = (VALUE)data;
  VALUE tracer = rb_iv_get(self, "@tracer");
  VALUE active_span = rb_funcall(tracer, rb_intern("active_span"), 0);
  if (NIL_P(active_span)) {
    return;
  }

  VALUE raised_exception = rb_tracearg_raised_exception(rb_tracearg_from_tracepoint(tp));
  VALUE filter_function = rb_iv_get(self, "@filter_function");

  if (RTEST(rb_funcall(filter_function, rb_intern("call"), 1, raised_exception))) {
    VALUE span_event = _generate_span_event(self, raised_exception);
    VALUE collector = rb_iv_get(self, "@collector");
    add_span_event(collector, rb_funcall(active_span, rb_intern("span_id"), 0) , raised_exception, span_event);
    rb_funcall(active_span, rb_intern("record"), 1, span_event);
  }
}
