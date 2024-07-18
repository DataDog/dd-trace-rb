#pragma once

#include <stdbool.h>
#include <errno.h>
#include "ruby_helpers.h"

#define SECONDS_AS_NS(value) (value * 1000 * 1000 * 1000L)
#define MILLIS_AS_NS(value) (value * 1000 * 1000L)

#define RAISE_ON_FAILURE true
#define DO_NOT_RAISE_ON_FAILURE false

#define INVALID_TIME -1

typedef struct {
  long system_epoch_ns_reference;
  long delta_to_epoch_ns;
} monotonic_to_system_epoch_state;

#define MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER {.system_epoch_ns_reference = INVALID_TIME, .delta_to_epoch_ns = INVALID_TIME}

// Safety: This function is assumed never to raise exceptions by callers when raise_on_failure == false
inline long retrieve_clock_as_ns(clockid_t clock_id, bool raise_on_failure) {
  struct timespec clock_value;

  if (clock_gettime(clock_id, &clock_value) != 0) {
    if (raise_on_failure) ENFORCE_SUCCESS_GVL(errno);
    return 0;
  }

  return clock_value.tv_nsec + SECONDS_AS_NS(clock_value.tv_sec);
}

// Safety: These functions are assumed never to raise exceptions by callers when raise_on_failure == false
inline long monotonic_wall_time_now_ns(bool raise_on_failure) { return retrieve_clock_as_ns(CLOCK_MONOTONIC, raise_on_failure); }
inline long monotonic_coarse_wall_time_now_ns(bool raise_on_failure) { return retrieve_clock_as_ns(CLOCK_MONOTONIC_COARSE, raise_on_failure); }
inline long system_epoch_time_now_ns(bool raise_on_failure) { return retrieve_clock_as_ns(CLOCK_REALTIME,  raise_on_failure); }

long monotonic_to_system_epoch_ns(monotonic_to_system_epoch_state *state, long monotonic_wall_time_ns);
