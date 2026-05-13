#pragma once

// This helper is used by the Datadog::Profiling::Collectors::ThreadContext to store data used when profiling the GVL.
// It's tested through that class' interfaces.
// ---

#include "extconf.h"

#if !defined(NO_GVL_INSTRUMENTATION) && !defined(USE_GVL_PROFILING_3_2_WORKAROUNDS) // Ruby 3.3+
  #include <ruby.h>
  #include <ruby/thread.h>
  #include "datadog_ruby_common.h"

  typedef struct { VALUE thread; } gvl_profiling_thread;
  extern rb_internal_thread_specific_key_t gvl_waiting_tls_key;
  // Per-thread "state + version" word, updated on every GVL state transition. The encoding is:
  //   - low bit:  current state (1 = currently suspended, 0 = currently running)
  //   - bits 1+:  monotonic event counter (incremented on every SUSPENDED or RESUMED)
  // The hooks set the state bit explicitly rather than relying on parity, so the encoding stays
  // correct even when initialize_context clears the slot for a thread that was already mid-
  // suspension before the profiler observed it. The sampler reads the word once: low bit is the
  // current state, equality with its per-thread snapshot means no transitions since the last
  // sample. Together this answers "did not have the GVL last sample and did not acquire it since
  // then" with no wall-time read in the hot SUSPENDED hook path.
  extern rb_internal_thread_specific_key_t gvl_state_change_count_tls_key;

  void gvl_profiling_init(void);

  static inline gvl_profiling_thread thread_from_thread_object(VALUE thread) {
    return (gvl_profiling_thread) {.thread = thread};
  }

  static inline gvl_profiling_thread thread_from_event(const rb_internal_thread_event_data_t *event_data) {
    return thread_from_thread_object(event_data->thread);
  }

  static inline intptr_t gvl_profiling_state_get(gvl_profiling_thread thread) {
    return (intptr_t) rb_internal_thread_specific_get(thread.thread, gvl_waiting_tls_key);
  }

  static inline void gvl_profiling_state_set(gvl_profiling_thread thread, intptr_t value) {
    rb_internal_thread_specific_set(thread.thread, gvl_waiting_tls_key, (void *) value);
  }

  static inline long gvl_state_change_count_get(gvl_profiling_thread thread) {
    return (long) (intptr_t) rb_internal_thread_specific_get(thread.thread, gvl_state_change_count_tls_key);
  }

  static inline void gvl_state_change_count_set(gvl_profiling_thread thread, long value) {
    rb_internal_thread_specific_set(thread.thread, gvl_state_change_count_tls_key, (void *) (intptr_t) value);
  }

  // Called by the SUSPENDED internal-thread-event hook. Bumps the event counter (so the whole
  // word changes) and sets the state bit to "suspended".
  static inline void gvl_state_change_count_mark_suspended(gvl_profiling_thread thread) {
    long counter_portion = gvl_state_change_count_get(thread) >> 1;
    gvl_state_change_count_set(thread, ((counter_portion + 1) << 1) | 1L);
  }

  // Called by the RESUMED internal-thread-event hook. Bumps the event counter and clears the
  // state bit to "running".
  static inline void gvl_state_change_count_mark_resumed(gvl_profiling_thread thread) {
    long counter_portion = gvl_state_change_count_get(thread) >> 1;
    gvl_state_change_count_set(thread, (counter_portion + 1) << 1);
  }
#endif

#ifdef USE_GVL_PROFILING_3_2_WORKAROUNDS // Ruby 3.2
  typedef struct { void *thread; } gvl_profiling_thread;
  extern __thread gvl_profiling_thread gvl_waiting_tls;

  static inline void gvl_profiling_init(void) { }

  // NOTE: This is a hack that relies on the knowledge that on Ruby 3.2 the
  // RUBY_INTERNAL_THREAD_EVENT_READY and RUBY_INTERNAL_THREAD_EVENT_RESUMED events always get called on the thread they
  // are about. Thus, we can use our thread local storage hack to get this data, even though the event doesn't include it.
  static inline gvl_profiling_thread thread_from_event(DDTRACE_UNUSED const void *event_data) {
    return gvl_waiting_tls;
  }

  void gvl_profiling_state_thread_tracking_workaround(void);
  gvl_profiling_thread gvl_profiling_state_maybe_initialize(void);

  // Implementing these on Ruby 3.2 requires access to private VM things, so the following methods are
  // implemented in `private_vm_api_access.c`
  gvl_profiling_thread thread_from_thread_object(VALUE thread);
  intptr_t gvl_profiling_state_get(gvl_profiling_thread thread);
  void gvl_profiling_state_set(gvl_profiling_thread thread, intptr_t value);
#endif

#ifndef NO_GVL_INSTRUMENTATION // For all Rubies supporting GVL profiling (3.2+)
  static inline intptr_t gvl_profiling_state_thread_object_get(VALUE thread) {
    return gvl_profiling_state_get(thread_from_thread_object(thread));
  }

  static inline void gvl_profiling_state_thread_object_set(VALUE thread, intptr_t value) {
    gvl_profiling_state_set(thread_from_thread_object(thread), value);
  }
#endif

#if !defined(NO_GVL_INSTRUMENTATION) && !defined(USE_GVL_PROFILING_3_2_WORKAROUNDS) // Ruby 3.3+
  static inline long gvl_state_change_count_thread_object_get(VALUE thread) {
    return gvl_state_change_count_get(thread_from_thread_object(thread));
  }

  static inline void gvl_state_change_count_thread_object_set(VALUE thread, long value) {
    gvl_state_change_count_set(thread_from_thread_object(thread), value);
  }
#endif
