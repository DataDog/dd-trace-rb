#include <errno.h>
#include <time.h>

#include "ruby_helpers.h"
#include "time_helpers.h"

// Safety: This function is assumed never to raise exceptions by callers when raise_on_failure == false
long monotonic_wall_time_now_ns(bool raise_on_failure) {
  struct timespec current_monotonic;

  if (clock_gettime(CLOCK_MONOTONIC, &current_monotonic) != 0) {
    if (raise_on_failure) ENFORCE_SUCCESS_GVL(errno);
    return 0;
  }

  return current_monotonic.tv_nsec + SECONDS_AS_NS(current_monotonic.tv_sec);
}
