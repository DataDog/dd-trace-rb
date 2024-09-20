#include <ruby.h>
#include <ruby/thread.h>
#include "gvl_profiling_helper.h"

#if !defined(NO_GVL_INSTRUMENTATION) // Ruby 3.3+

rb_internal_thread_specific_key_t gvl_waiting_tls_key;

void gvl_profiling_init(void) {
  gvl_waiting_tls_key = rb_internal_thread_specific_key_create();
}

#endif

