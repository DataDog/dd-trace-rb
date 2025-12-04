#include <ruby.h>
#include <stdbool.h>
#include "ruby_internal.h"
#include "ruby_helpers.h"

#ifndef DDTRACE_UNUSED
#define DDTRACE_UNUSED  __attribute__((unused))
#endif

struct ddtrace_di_os_each_struct {
    VALUE array;
};

static int ddtrace_di_os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
    struct ddtrace_di_os_each_struct *oes = (struct ddtrace_di_os_each_struct *)data;
    VALUE array = oes->array;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        if (ddtrace_imemo_iseq_p(v)) {
            VALUE iseq = rb_iseqw_new((void *) v);
            rb_ary_push(array, iseq);
        }
    }

    return 0;
}

static VALUE all_iseqs(DDTRACE_UNUSED VALUE _self) {
    struct ddtrace_di_os_each_struct oes;

    oes.array = rb_ary_new();
    rb_objspace_each_objects(ddtrace_di_os_obj_of_i, &oes);
    RB_GC_GUARD(oes.array);
    return oes.array;
}

void di_init(VALUE di_module) {
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
}
