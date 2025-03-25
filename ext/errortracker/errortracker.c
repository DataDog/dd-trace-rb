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

void DDTRACE_EXPORT Init_errortracker(void) {
    VALUE datadog_module = rb_define_module("Datadog");
    VALUE core_module = rb_define_module_under(datadog_module, "Core");
    VALUE errortracking_module = rb_define_module_under(core_module, "Errortracking");
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

  ENFORCE_TYPE(to_instrument, T_STRING);
  ENFORCE_TYPE(to_instrument_modules, T_ARRAY);

  VALUE collector = rb_class_new_instance(0, NULL, rb_path2class("Datadog::Core::Errortracking::Collector"));
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

// static VALUE protected_call(VALUE args_val) {
//   VALUE *f_args = (VALUE *)args_val;
//   VALUE args[2] = {
//     ID2SYM(rb_intern("name")),
//     rb_hash_new()
//   };
//   rb_hash_aset(args[1], ID2SYM(rb_intern("attributes")), f_args[1]);

//   return rb_funcallv_kw(f_args[0], rb_intern("new"), 2, args, RB_PASS_KEYWORDS);
// }

// VALUE args[2] = { span_event_class, attributes };
// int error = 0;
// VALUE result = rb_protect(protected_call, (VALUE)args, &error);
// if (error) {
//     VALUE err = rb_errinfo();
//     VALUE err_str = rb_funcall(err, rb_intern("to_s"), 0);
//     rb_warn("Error: %s", StringValueCStr(err_str));
//     rb_set_errinfo(Qnil);
// }


static VALUE _generate_span_event(DDTRACE_UNUSED VALUE _self, VALUE exception) {
    /** too much evaluation for nothing todo */
    VALUE datadog_module = rb_const_get(rb_cObject, rb_intern("Datadog"));
    VALUE core_module = rb_const_get(datadog_module, rb_intern("Core"));
    VALUE error_class = rb_const_get(core_module, rb_intern("Error"));
    VALUE formatted_exception = rb_funcallv(error_class,  rb_intern("build_from"), 1, &exception);
    VALUE tracing_module = rb_const_get(datadog_module, rb_intern("Tracing"));
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

    VALUE span_event_args[2] = {
      ID2SYM(rb_intern("exception")),
      rb_hash_new()
    };
    rb_hash_aset(span_event_args[1], ID2SYM(rb_intern("attributes")), attributes);

    // bundle exec rake clean compile && bundle exec 'DD_ERROR_TRACKING_REPORT_HANDLED_ERRORS=all ruby .tests/simple.rb'
    return rb_funcallv_kw(span_event_class, rb_intern("new"), 2, span_event_args, RB_PASS_KEYWORDS);
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

    add_span_event(collector, active_span , raised_exception, span_event);
  }
}
