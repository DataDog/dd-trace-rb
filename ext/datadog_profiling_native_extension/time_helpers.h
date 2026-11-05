#pragma once

#include <ruby.h>
#include <errno.h>
#include <stdbool.h>
#include <time.h>

#include "extconf.h"

#define SECONDS_AS_NS(value) ((value) * 1000L * 1000L * 1000L)
#define MILLIS_AS_NS(value)  ((value) * 1000L * 1000L)
#define MICROS_AS_NS(value)  ((value) * 1000L)

#define INVALID_TIME -1

typedef struct {
  // INVALID_TIME until the first conversion, and the only field used to decide if the state needs to be (re)computed
  long system_epoch_ns_reference;
  long delta_to_epoch_ns;
} monotonic_to_system_epoch_state;

#define MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER {.system_epoch_ns_reference = INVALID_TIME}

// clock_id MUST be one of CLOCK_REALTIME/CLOCK_MONOTONIC_FOR_PROFILING/CLOCK_MONOTONIC_COARSE_FOR_PROFILING
// as for those we're guaranteed to never see failures here unless something is really off
static inline long retrieve_clock_as_ns(clockid_t clock_id) {
  struct timespec clock_value;

  if (RB_UNLIKELY(clock_gettime(clock_id, &clock_value) != 0)) {
    rb_bug("[ddtrace] clock_gettime(%d) unexpectedly failed (errno=%d) but it should always succeed, libc/kernel bug?", (int) clock_id, errno);
  }

  return clock_value.tv_nsec + SECONDS_AS_NS(clock_value.tv_sec);
}

// CLOCK_MONOTONIC on macOS only has microsecond precision, CLOCK_MONOTONIC_RAW has nanosecond precision
#ifdef __APPLE__
  #define CLOCK_MONOTONIC_FOR_PROFILING CLOCK_MONOTONIC_RAW
  #define CLOCK_MONOTONIC_COARSE_FOR_PROFILING CLOCK_MONOTONIC_RAW_APPROX
#else
  #define CLOCK_MONOTONIC_FOR_PROFILING CLOCK_MONOTONIC
  #define CLOCK_MONOTONIC_COARSE_FOR_PROFILING CLOCK_MONOTONIC_COARSE
#endif

static inline long monotonic_wall_time_now_ns(void) { return retrieve_clock_as_ns(CLOCK_MONOTONIC_FOR_PROFILING); }
static inline long system_epoch_time_now_ns(void)   { return retrieve_clock_as_ns(CLOCK_REALTIME); }

// Coarse instants use CLOCK_MONOTONIC_COARSE on Linux which is expected to provide resolution in the millisecond range:
// https://docs.redhat.com/en/documentation/red_hat_enterprise_linux_for_real_time/7/html/reference_guide/sect-posix_clocks#Using_clock_getres_to_compare_clock_resolution
// We introduce here a separate type for it, so as to make it harder to misuse/more explicit when these timestamps are used

typedef struct {
  long timestamp_ns;
} coarse_instant;

static inline coarse_instant to_coarse_instant(long timestamp_ns) { return (coarse_instant) {.timestamp_ns = timestamp_ns}; }

static inline coarse_instant monotonic_coarse_wall_time_now_ns(void) {
  return to_coarse_instant(retrieve_clock_as_ns(CLOCK_MONOTONIC_COARSE_FOR_PROFILING));
}

long monotonic_to_system_epoch_ns(monotonic_to_system_epoch_state *state, long monotonic_wall_time_ns);
