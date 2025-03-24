#include <ruby.h>
#include "datadog_ruby_common.h"
#include "collector.h"


void collector_init(VALUE errortracking_module) {
    VALUE collector_class = rb_define_class_under(errortracking_module, "Collector", rb_cObject);
    rb_define_method(collector_class, "add_span_event", add_span_event, 3);
    rb_define_method(collector_class, "get_span_events", get_span_events, 1);
    rb_define_private_method(collector_class, "_clear_span", _clear_span, 1);
    rb_define_method(collector_class, "initialize", initialize, 0);
    rb_define_attr(collector_class, "storage", 1, 1);
}

VALUE initialize(VALUE self) {
    VALUE hash = rb_hash_new();
    rb_iv_set(self, "@storage", hash);
    return self;
}

VALUE _clear_span(VALUE self, VALUE span_id) {
    VALUE storage = rb_iv_get(self, "@storage");
    rb_hash_delete(storage, span_id);
    return Qnil;
}

VALUE get_span_events(VALUE self, VALUE span_id) {
    VALUE storage = rb_iv_get(self, "@storage");
    VALUE span_events_by_error = rb_hash_aref(storage, span_id);
    VALUE span_events = rb_ary_new();
    VALUE stored_span_events = rb_funcall(span_events_by_error, rb_intern("keys"), 0);
    for (long i = 0; i < RARRAY_LEN(stored_span_events); i++) {
        rb_ary_push(span_events, rb_ary_entry(stored_span_events, i));
    }
    return span_events;
}

VALUE add_span_event(VALUE self, VALUE span_id, VALUE error, VALUE span_event) {
    VALUE storage = rb_iv_get(self, "@storage");
    VALUE error_map;

    if (rb_hash_lookup(storage, span_id) == Qnil) {
        error_map = rb_hash_new();
        rb_hash_aset(storage, span_id, error_map);
    } else {
        error_map = rb_hash_aref(storage, span_id);
    }

    if (rb_hash_lookup(error_map, error) == Qnil) {
        rb_hash_aset(error_map, error, rb_hash_new());
    }
    rb_hash_aset(error_map, error, span_event);

    return Qnil;
}