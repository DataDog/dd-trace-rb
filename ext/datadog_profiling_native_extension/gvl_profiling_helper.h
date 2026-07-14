#pragma once

// This helper is used by the Datadog::Profiling::Collectors::ThreadContext to store data used when profiling the GVL.
// It's tested through that class' interfaces.
// ---

#include "extconf.h"

#include <ruby.h>

// Opaque to this header; the full definition lives in collectors_thread_context.c.
typedef struct per_thread_context per_thread_context;

#ifdef HAVE_RUBY_THREAD_STORAGE_API
  #include <ruby/thread.h>

  extern rb_internal_thread_specific_key_t per_thread_context_key;

  void per_thread_context_tls_init(void);

  static inline per_thread_context* get_per_thread_context(VALUE thread) {
    return rb_internal_thread_specific_get(thread, per_thread_context_key);
  }

  static inline void set_per_thread_context(VALUE thread, per_thread_context* value) {
    rb_internal_thread_specific_set(thread, per_thread_context_key, value);
  }
#else
  static inline void per_thread_context_tls_init(void) { }

  // Implementing these on Ruby 3.2 requires access to private VM things, so the following methods are
  // implemented in `private_vm_api_access.c`
  per_thread_context* get_per_thread_context(VALUE thread);
  void set_per_thread_context(VALUE thread, per_thread_context* value);
#endif
