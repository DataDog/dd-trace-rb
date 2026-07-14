#include <ruby.h>
#include <ruby/thread.h>

#include "datadog_ruby_common.h"
#include "gvl_profiling_helper.h"

#ifdef HAVE_RUBY_THREAD_STORAGE_API
  rb_internal_thread_specific_key_t per_thread_context_key;

  void per_thread_context_tls_init(void) {
    per_thread_context_key = rb_internal_thread_specific_key_create();
  }
#endif
