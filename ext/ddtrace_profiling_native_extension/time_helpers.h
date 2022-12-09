#pragma once

#define SECONDS_AS_NS(value) (value * 1000 * 1000 * 1000L)
#define MILLIS_AS_NS(value) (value * 1000 * 1000L)

#define RAISE_ON_FAILURE true
#define DO_NOT_RAISE_ON_FAILURE false

// Safety: This function is assumed never to raise exceptions by callers when raise_on_failure == false
long monotonic_wall_time_now_ns(bool raise_on_failure);
