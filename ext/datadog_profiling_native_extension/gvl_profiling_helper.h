#pragma once

// This helper is used by the Datadog::Profiling::Collectors::ThreadContext to store data used when profiling the GVL.
// It's tested through that class' interfaces.
// ---

#include "extconf.h"

#if !defined(NO_GVL_INSTRUMENTATION) // Ruby 3.3+

#include <ruby.h>
#include <ruby/thread.h>
#include "datadog_ruby_common.h"

typedef struct { VALUE thread; } gvl_profiling_thread;
extern rb_internal_thread_specific_key_t gvl_waiting_tls_key;

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

static inline intptr_t gvl_profiling_state_thread_object_get(VALUE thread) {
  return gvl_profiling_state_get(thread_from_thread_object(thread));
}

static inline void gvl_profiling_state_thread_object_set(VALUE thread, intptr_t value) {
  gvl_profiling_state_set(thread_from_thread_object(thread), value);
}
#endif
