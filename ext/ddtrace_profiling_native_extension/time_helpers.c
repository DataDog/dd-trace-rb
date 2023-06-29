#include <errno.h>
#include <time.h>

#include "ruby_helpers.h"
#include "time_helpers.h"

// Safety: This function is assumed never to raise exceptions by callers when raise_on_failure == false
long retrieve_clock_as_ns(clockid_t clock_id, bool raise_on_failure) {
  struct timespec clock_value;

  if (clock_gettime(clock_id, &clock_value) != 0) {
    if (raise_on_failure) ENFORCE_SUCCESS_GVL(errno);
    return 0;
  }

  return clock_value.tv_nsec + SECONDS_AS_NS(clock_value.tv_sec);
}

long monotonic_wall_time_now_ns(bool raise_on_failure) { return retrieve_clock_as_ns(CLOCK_MONOTONIC, raise_on_failure); }
long system_epoch_time_now_ns(bool raise_on_failure)   { return retrieve_clock_as_ns(CLOCK_REALTIME,  raise_on_failure); }
