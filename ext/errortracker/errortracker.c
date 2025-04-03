#include <ruby.h>
#include <ruby/debug.h>
#include "extconf.h"

#include "datadog_ruby_common.h"
#include "filters.h"
#include "collector.h"

static VALUE _native_start(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_stop(DDTRACE_UNUSED VALUE _self);
static VALUE _generate_span_event(DDTRACE_UNUSED VALUE _self, VALUE exception);
static VALUE _add_instrumented_file(VALUE self, VALUE file_name);
static void tracepoint_callback(VALUE tp, void* data);
static void errortracker_init(VALUE errortracking_module);
static void initialize_constants_errortracker(void);

// Static variables at module level
static VALUE datadog_module = Qnil;
static VALUE core_module = Qnil;
static VALUE error_class = Qnil;
static VALUE tracing_module = Qnil;
static VALUE span_event_class = Qnil;
static VALUE type_sym = Qnil;
static VALUE message_sym = Qnil;
static VALUE stacktrace_sym = Qnil;
static VALUE exception_sym = Qnil;
static VALUE attributes_sym = Qnil;

static ID at_active_span_id;
static ID at_call_id;
static ID at_build_from_id;
static ID at_type_id;
static ID at_message_id;
static ID at_backtrace_id;
static ID at_new_id;

static void initialize_constants_errortracker(void) {
  datadog_module = rb_const_get(rb_cObject, rb_intern_const("Datadog"));
  core_module = rb_const_get(datadog_module, rb_intern_const("Core"));
  error_class = rb_const_get(core_module, rb_intern_const("Error"));
  tracing_module = rb_const_get(datadog_module, rb_intern_const("Tracing"));
  span_event_class = rb_const_get(tracing_module, rb_intern_const("SpanEvent"));

  type_sym = ID2SYM(rb_intern_const("type"));
  message_sym = ID2SYM(rb_intern_const("message"));
  stacktrace_sym = ID2SYM(rb_intern_const("stacktrace"));
  exception_sym = ID2SYM(rb_intern_const("exception"));
  attributes_sym = ID2SYM(rb_intern_const("attributes"));

  at_active_span_id = rb_intern_const("active_span");
  at_call_id = rb_intern_const("call");
  at_build_from_id = rb_intern_const("build_from");
  at_type_id = rb_intern_const("type");
  at_message_id = rb_intern_const("message");
  at_backtrace_id = rb_intern_const("backtrace");
  at_new_id = rb_intern_const("new");
}

void DDTRACE_EXPORT Init_errortracker(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE core_module = rb_define_module_under(datadog_module, "Core");
  VALUE errortracking_module = rb_define_module_under(core_module, "Errortracking");

  errortracker_init(errortracking_module);
  collector_init(errortracking_module);
  filters_init();
  initialize_constants_errortracker();
}

static void errortracker_init(VALUE errortracking_module) {
  VALUE errortracker_class = rb_define_class_under(errortracking_module, "Component", rb_cObject);

  rb_define_singleton_method(errortracker_class, "_native_start", _native_start, -1);
  rb_define_singleton_method(errortracker_class, "_native_stop", _native_stop, 0);
  rb_define_singleton_method(errortracker_class, "_add_instrumented_file", _add_instrumented_file, 1);

  rb_define_attr(errortracker_class, "tracepoint", 1, 1);
  rb_define_attr(errortracker_class, "tracer", 1, 1);
  rb_define_attr(errortracker_class, "collector", 1, 1);
  rb_define_attr(errortracker_class, "instrumented_files", 1, 1);
}

static VALUE _add_instrumented_file(VALUE self, VALUE file_name) {
  VALUE instrumented_files = rb_iv_get(self, "@instrumented_files");
  rb_hash_aset(instrumented_files, file_name, Qtrue);
  return Qnil;
}

static VALUE _native_start(int argc, VALUE* argv, VALUE self) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (NIL_P(options)) options = rb_hash_new();

  VALUE tracer = rb_hash_fetch(options, ID2SYM(rb_intern("tracer")));
  VALUE to_instrument = rb_hash_fetch(options, ID2SYM(rb_intern("to_instrument")));
  VALUE to_instrument_modules = rb_hash_fetch(options, ID2SYM(rb_intern("to_instrument_modules")));

  ENFORCE_TYPE(to_instrument, T_STRING);
  ENFORCE_TYPE(to_instrument_modules, T_ARRAY);

  VALUE collector = rb_class_new_instance(0, NULL, rb_path2class("Datadog::Core::Errortracking::Collector"));
  rb_iv_set(self, "@collector", collector);
  rb_iv_set(self, "@tracer", tracer);

  VALUE filter_function;
  if (RARRAY_LEN(to_instrument_modules) > 0) {
    rb_iv_set(self, "@instrumented_files", rb_hash_new());
    filter_function = generate_filter(self, to_instrument, rb_iv_get(self, "@instrumented_files"));
  } else {
    filter_function = generate_filter(self, to_instrument, Qnil);
  }

  rb_iv_set(self, "@filter_function", filter_function);
  double ruby_version = RFLOAT_VALUE(rb_const_get(rb_cObject, rb_intern("RUBY_VERSION")));
  VALUE tracepoint;
  if (ruby_version >= 3.3) {
    #ifdef RUBY_EVENT_RESCUE
    tracepoint = rb_tracepoint_new(Qnil, RUBY_EVENT_RESCUE, tracepoint_callback, (void*)self);
    #else
    tracepoint = Qnil;
    #endif
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
  VALUE formatted_exception = rb_funcall(error_class, at_build_from_id, 1, exception);

  VALUE type = rb_funcall(formatted_exception, at_type_id, 0);
  VALUE message = rb_funcall(formatted_exception, at_message_id, 0);
  VALUE stacktrace = rb_funcall(formatted_exception, at_backtrace_id, 0);

  VALUE attributes = rb_hash_new();
  rb_hash_aset(attributes, type_sym, type);
  rb_hash_aset(attributes, message_sym, message);
  rb_hash_aset(attributes, stacktrace_sym, stacktrace);

  VALUE span_event_args[2] = {
    exception_sym,
    rb_hash_new()
  };
  rb_hash_aset(span_event_args[1], attributes_sym, attributes);

  return rb_funcallv_kw(span_event_class, at_new_id, 2, span_event_args, RB_PASS_KEYWORDS);
}

static void tracepoint_callback(VALUE tp, void* data) {
  VALUE self = (VALUE)data;
  VALUE tracer = rb_iv_get(self, "@tracer");
  VALUE active_span = rb_funcall(tracer, at_active_span_id, 0);

  if (NIL_P(active_span)) {
      return;
  }

  VALUE raised_exception = rb_tracearg_raised_exception(rb_tracearg_from_tracepoint(tp));
  VALUE rescue_file_path = rb_tracearg_path(rb_tracearg_from_tracepoint(tp));
  VALUE filter_function = rb_iv_get(self, "@filter_function");

  if (RTEST(rb_funcall(filter_function, at_call_id, 1, rescue_file_path))) {
    VALUE span_event = _generate_span_event(self, raised_exception);
    VALUE collector = rb_iv_get(self, "@collector");
      add_span_event(collector, active_span, raised_exception, span_event);
    }
}
