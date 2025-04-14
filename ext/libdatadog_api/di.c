#include <ruby.h>
#include <stdbool.h>
#include "ruby_internal.h"

#ifndef DDTRACE_UNUSED
#define DDTRACE_UNUSED  __attribute__((unused))
#endif

#define IMEMO_TYPE_ISEQ 7

struct ddtrace_di_os_each_struct {
    VALUE array;
};

static inline int ddtrace_di_imemo_type(VALUE imemo) {
  // This mask is the same between Ruby 2.5 and 3.3-preview3. Furthermore, the intention of this method is to be used
  // to call `rb_imemo_name` which correctly handles invalid numbers so even if the mask changes in the future, at most
  // we'll get incorrect results (and never a VM crash)
  #define IMEMO_MASK   0x0f
  return (RBASIC(imemo)->flags >> FL_USHIFT) & IMEMO_MASK;
}

// Returns whether the argument is an IMEMO of type ISEQ.
static inline bool ddtrace_di_imemo_iseq_p(VALUE v) {
    if (rb_objspace_internal_object_p(v)) {
        if (RB_TYPE_P(v, T_IMEMO)) {
            if (ddtrace_di_imemo_type(v) == IMEMO_TYPE_ISEQ) {
                return true;
            }
        }
    }
    return false;
}

static int ddtrace_di_os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
    struct ddtrace_di_os_each_struct *oes = (struct ddtrace_di_os_each_struct *)data;
    VALUE array = oes->array;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        if (ddtrace_di_imemo_iseq_p(v)) {
            VALUE iseq = rb_iseqw_new((void *) v);
            rb_ary_push(array, iseq);
        }
    }

    return 0;
}

static VALUE loaded_file_iseqs(DDTRACE_UNUSED VALUE _self) {
    struct ddtrace_di_os_each_struct oes;

    oes.array = rb_ary_new();
    rb_objspace_each_objects(ddtrace_di_os_obj_of_i, &oes);
    RB_GC_GUARD(oes.array);
    return oes.array;
}

void di_init(VALUE di_module) {
  rb_define_singleton_method(di_module, "loaded_file_iseqs", loaded_file_iseqs, 0);
}
