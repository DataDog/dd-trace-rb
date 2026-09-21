#pragma once

#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <pthread.h>
#include <stdio.h>

#include "time_helpers.h"

// On macOS the default scheduler wake latency for a timeshare thread is ~1-2ms,
// so nanosleep regularly overshoots a 10ms request by ~2ms. Marking the worker
// thread with THREAD_TIME_CONSTRAINT_POLICY tells the scheduler this thread has
// a periodic deadline; the kernel then wakes it close to the requested time.
//
// This only affects the sampler worker thread. We pair it with a demote call
// before the thread can be reused by Ruby for unrelated Ruby threads (see the
// SIGPROF unblock dance in _native_sampling_loop).
static inline void promote_sampler_thread_to_realtime(uint64_t period_ns) {
  mach_timebase_info_data_t timebase = (mach_timebase_info_data_t) {};
  mach_timebase_info(&timebase);

  // ns -> mach ticks: each mach tick is (numer/denom) ns, so divide by that.
  #define NS_TO_MACH_TICKS(ns) ((uint32_t) (((uint64_t)(ns) * (uint64_t) timebase.denom) / (uint64_t) timebase.numer))

  struct thread_time_constraint_policy policy = {
    .period      = NS_TO_MACH_TICKS(period_ns),
    .computation = NS_TO_MACH_TICKS(MICROS_AS_NS(200)),  // 200us upper bound on the work we do per period
    .constraint  = NS_TO_MACH_TICKS(MILLIS_AS_NS(1)),    // wake us within 1ms of the deadline
    .preemptible = TRUE,
  };

  #undef NS_TO_MACH_TICKS

  kern_return_t kr = thread_policy_set(
    pthread_mach_thread_np(pthread_self()),
    THREAD_TIME_CONSTRAINT_POLICY,
    (thread_policy_t) &policy,
    THREAD_TIME_CONSTRAINT_POLICY_COUNT
  );
  if (kr != KERN_SUCCESS) {
    // Non-fatal: we'll fall back to the default scheduler behavior (overshoot ~2ms).
    fprintf(stderr, "[ddtrace] Failed to set real-time policy on profiler sampler thread (kr=%d); sample cadence may be imprecise\n", kr);
  }
}

static inline void demote_sampler_thread_from_realtime(void) {
  struct thread_standard_policy policy = {.no_data = 0};
  thread_policy_set(
    pthread_mach_thread_np(pthread_self()),
    THREAD_STANDARD_POLICY,
    (thread_policy_t) &policy,
    THREAD_STANDARD_POLICY_COUNT
  );
}
