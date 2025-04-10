#include <ruby.h>
#include "datadog_ruby_common.h"
#include "collector.h"

// A collector in charge of storing the span_event for every span
//
// We do not add directly the span_events to the span for deduplication purpose
// The collector is also responsible of suscribing the on_finish/on_error events.
// NOTE: We subscribe to the events here as it is simpler to know when this
//       the first time we record a handled error for a span

// symbols used within the file
static ID at_id_id;
static ID at_add_span_event_id;
static ID at_values_id;
static ID at_events_id;
static ID at_after_stop_id;
static ID at_on_error_id;
static ID at_subscribe_id;
static ID at_span_events_id;

static void initialize_constants_collector(void) {
  at_id_id = rb_intern_const("id");
  at_add_span_event_id = rb_intern_const("add_span_event");
  at_values_id = rb_intern_const("values");
  at_events_id = rb_intern_const("events");
  at_after_stop_id = rb_intern_const("after_stop");
  at_on_error_id = rb_intern_const("on_error");
  at_subscribe_id = rb_intern_const("subscribe");
  at_span_events_id = rb_intern_const("span_events");
}

void collector_init(VALUE errortracking_module) {
  // Define Collector class
  VALUE collector_class = rb_define_class_under(errortracking_module, "Collector", rb_cObject);
  rb_define_method(collector_class, "add_span_event", add_span_event, 3);
  rb_define_method(collector_class, "get_span_events", get_span_events, 1);
  rb_define_private_method(collector_class, "_clear_span", _clear_span, 1);
  rb_define_method(collector_class, "initialize", initialize, 0);

  // Storage is a Hash<span_id[int], Hash<Error, SpanEvent>>
  rb_define_attr(collector_class, "storage", 1, 1);

  // Blocks to execute on on_finish/on_error event.
  rb_define_attr(collector_class, "after_stop_block", 1, 1);
  rb_define_attr(collector_class, "on_error_block", 1, 1);

  initialize_constants_collector();
}

static VALUE after_stop_callback(VALUE span, VALUE self) {
  // This function will add all the span_events to the span
  VALUE span_id = rb_funcall(span, at_id_id, 0);
  VALUE span_events = get_span_events(self, span_id);
  if (!NIL_P(span_events)) {
    long len = RARRAY_LEN(span_events);
    for (long i = 0; i < len; i++) {
        rb_funcall(span, at_add_span_event_id, 1, rb_ary_entry(span_events, i));
    }
    _clear_span(self, span_id);
  }
  return Qnil;
}

static VALUE on_error_callback(DDTRACE_UNUSED VALUE _yielded_arg, DDTRACE_UNUSED VALUE _self, int argc, const VALUE *argv) {
  // When an error escapes a span, the tracer will
  if (argc == 2) {
    VALUE span_op = argv[0];
    VALUE span_events = rb_funcall(span_op, at_span_events_id, 0);
    rb_ary_pop(span_events);
  }
  return Qnil;
}

VALUE initialize(VALUE self) {
  VALUE hash = rb_hash_new();
  rb_iv_set(self, "@storage", hash);

  VALUE after_stop_proc = rb_proc_new((VALUE(*)(ANYARGS))after_stop_callback, self);
  rb_iv_set(self, "@after_stop_block", after_stop_proc);

  VALUE on_error_proc = rb_proc_new((VALUE(*)(ANYARGS))on_error_callback, self);
  rb_iv_set(self, "@on_error_block", on_error_proc);

  return self;
}

VALUE _clear_span(VALUE self, VALUE span_id) {
  VALUE storage = rb_iv_get(self, "@storage");
  rb_hash_delete(storage, span_id);
  return Qnil;
}

VALUE get_span_events(VALUE self, VALUE span_id) {
  VALUE storage = rb_iv_get(self, "@storage");
  VALUE span_events_by_error = rb_hash_lookup(storage, span_id);
  if (NIL_P(span_events_by_error)) {
    return Qnil;
  }
  return rb_funcall(span_events_by_error, at_values_id, 0);
}

VALUE add_span_event(VALUE self, VALUE active_span, VALUE error, VALUE span_event) {
  VALUE storage = rb_iv_get(self, "@storage");
  VALUE span_id = rb_funcall(active_span, at_id_id, 0);
  VALUE error_map = rb_hash_lookup(storage, span_id);

  printf("adding a span event\n");
  if (NIL_P(error_map)) {
    error_map = rb_hash_new();
    rb_hash_aset(storage, span_id, error_map);

    // Subscribe events
    VALUE events = rb_funcall(active_span, at_events_id, 0);
    VALUE after_stop_event = rb_funcall(events, at_after_stop_id, 0);
    VALUE on_error_event = rb_funcall(events, at_on_error_id, 0);

    VALUE after_stop_block = rb_iv_get(self, "@after_stop_block");
    VALUE on_error_block = rb_iv_get(self, "@on_error_block");

    rb_funcall_with_block(after_stop_event, at_subscribe_id, 0, NULL , after_stop_block);
    rb_funcall_with_block(on_error_event, at_subscribe_id, 0, NULL , on_error_block);
  }
  // Store the span_event directly with the error as key
  rb_hash_aset(error_map, error, span_event);

  return Qnil;
}