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
    rb_define_attr(collector_class, "after_stop_block", 1, 1);
    rb_define_attr(collector_class, "on_error_block", 1, 1);
}

static VALUE after_stop_callback(VALUE span, VALUE self) {
    VALUE span_id = rb_funcall(span, rb_intern("id"), 0);
    VALUE span_events = get_span_events(self, span_id);
    long len = RARRAY_LEN(span_events);
    for (int i = 0; i < len; i++) {
        rb_funcall(span, rb_intern("add_span_event"), 1, rb_ary_entry(span_events, i));
    }
    return Qnil;
}

static VALUE on_error_callback(VALUE yielded_arg, VALUE self, int argc, const VALUE *argv) {
    if (argc == 2) {
        VALUE span_op = argv[0];
        VALUE span_events = rb_funcall(span_op, rb_intern("span_events"), 0);
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
    VALUE span_events_by_error = rb_hash_aref(storage, span_id);
    VALUE span_events = rb_ary_new();
    VALUE stored_span_events = rb_funcall(span_events_by_error, rb_intern("values"), 0);
    for (long i = 0; i < RARRAY_LEN(stored_span_events); i++) {
        rb_ary_push(span_events, rb_ary_entry(stored_span_events, i));
    }
    return span_events;
}

static VALUE protected_call(VALUE args_val) {
    VALUE *args = (VALUE *) args_val;
    return rb_funcall_with_block(args[0], rb_intern("subscribe"), 0, NULL , args[1]);
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

VALUE add_span_event(VALUE self, VALUE active_span, VALUE error, VALUE span_event) {
    VALUE storage = rb_iv_get(self, "@storage");
    VALUE span_id = rb_funcall(active_span, rb_intern("id"), 0);
    VALUE error_map;

    if (rb_hash_lookup(storage, span_id) == Qnil) {
        error_map = rb_hash_new();
        rb_hash_aset(storage, span_id, error_map);
        // suscribe events
        VALUE events = rb_funcall(active_span, rb_intern("events"), 0);
        VALUE after_stop_event = rb_funcall(events, rb_intern("after_stop"), 0);
        VALUE on_error_event = rb_funcall(events, rb_intern("on_error"), 0);

        VALUE after_stop_block = rb_iv_get(self, "@after_stop_block");
        VALUE on_error_block = rb_iv_get(self, "@on_error_block");

        rb_funcall_with_block(after_stop_event, rb_intern("subscribe"), 0, NULL , after_stop_block);
        rb_funcall_with_block(on_error_event, rb_intern("subscribe"), 0, NULL , on_error_block);
    } else {
        error_map = rb_hash_aref(storage, span_id);
    }

    if (rb_hash_lookup(error_map, error) == Qnil) {
        rb_hash_aset(error_map, error, rb_hash_new());
    }
    rb_hash_aset(error_map, error, span_event);
    return Qnil;
}