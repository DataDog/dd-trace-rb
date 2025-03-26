#include "ruby_internal.h"

struct os_each_struct {
    VALUE array;
};

static inline int ddtrace_imemo_type(VALUE imemo) {
  // This mask is the same between Ruby 2.5 and 3.3-preview3. Furthermore, the intention of this method is to be used
  // to call `rb_imemo_name` which correctly handles invalid numbers so even if the mask changes in the future, at most
  // we'll get incorrect results (and never a VM crash)
  #define IMEMO_MASK   0x0f
  return (RBASIC(imemo)->flags >> FL_USHIFT) & IMEMO_MASK;
}

static int
os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
    struct os_each_struct *oes = (struct os_each_struct *)data;
    VALUE array = oes->array;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        if (rb_objspace_internal_object_p(v)) {
            if (RB_TYPE_P(v, T_IMEMO)) {
                if (ddtrace_imemo_type(v)==7) {
                    //puts("it's an iseq imemo thing");
                    VALUE iseq = rb_iseqw_new((void *) v);
                    rb_ary_push(array, iseq);
                }
            }
        }
    }

    return 0;
}

static VALUE get_iseqs(VALUE self) {
    struct os_each_struct oes;

    oes.array = rb_ary_new();
    rb_objspace_each_objects(os_obj_of_i, &oes);
    return oes.array;
}
