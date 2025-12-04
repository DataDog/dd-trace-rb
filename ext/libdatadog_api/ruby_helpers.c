#include <stdbool.h>
#include "ruby_internal.h"
#include "ruby_helpers.h"

inline int ddtrace_imemo_type(VALUE imemo) {
  // This mask is the same between Ruby 2.5 and 3.3-preview3. Furthermore, the intention of this method is to be used
  // to call `rb_imemo_name` which correctly handles invalid numbers so even if the mask changes in the future, at most
  // we'll get incorrect results (and never a VM crash)
  return (RBASIC(imemo)->flags >> FL_USHIFT) & IMEMO_MASK;
}

// Returns whether the argument is an IMEMO of type ISEQ.
inline bool ddtrace_imemo_iseq_p(VALUE v) {
    if (rb_objspace_internal_object_p(v)) {
        if (RB_TYPE_P(v, T_IMEMO)) {
            if (ddtrace_imemo_type(v) == IMEMO_TYPE_ISEQ) {
                return true;
            }
        }
    }
    return false;
}
