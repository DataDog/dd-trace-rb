#include <ruby.h>

#include "collectors_dynamic_sampling_rate.h"
#include "helpers.h"
#include "ruby_helpers.h"
#include "time_helpers.h"

// Used to pace the rate of profiling samples based on the last observed time for a sample.
//
// This file implements the native bits of the Datadog::Profiling::Collectors::DynamicSamplingRate module, and is
// only exposed to Ruby for testing (it's always and only invoked by other C code in production).

// ---
// ## Dynamic Sampling Rate
//
// Our profilers get deployed in quite unpredictable situations in terms of system resources. While they can provide key
// information to help customers solve their performance problems, the profilers must always be careful not to make
// performance problems worse. This is where the idea of a dynamic sampling rate comes in.
//
// Instead of sampling at a fixed sample rate, the actual sampling rate should be decided by also observing the impact
// that running the profiler is having. This protects against issues such as the profiler being deployed in very busy
// machines or containers with unrealistic CPU restrictions.
//
// ### Implementation
//
// The APIs exposed by this file are used by the `CpuAndWallTimeWorker`.
//
// The main idea of the implementation below is the following: whenever the profiler takes a sample, the time we spent
// sampling and the current wall-time are recorded by calling one of the `dynamic_sampling_rate_after_sample*()`
// functions.
//
// Inside `dynamic_sampling_rate_after_sample*()` functions, timing values are combined to decide a future wall-time
// before which we should not sample. That is, we may decide that the next sample should happen no less than 200ms from now.
//
// We currently have 2 flavours of these functions:
// * `dynamic_sampling_rate_after_sample_continuous()` - This function operates under the assumption that, if desired
//   we could be continuously sampling. In other words, we own the decision of when to sample and thus the overhead
//   is a direct result of how much a single sample takes and how often we choose to do this.
// * `dynamic_sampling_rate_after_sample_discrete()` - This function operates under the assumption that sampling
//   cannot be done at will and has to align with discrete and distinct sampling opportunities (e.g. allocation
//   events). Thus overhead calculations have to take into account the approximate interval between these opportunities
//   which we do by keeping an exponential moving average of the times between consecutive `dynamic_sampling_rate_should_sample`
//   calls.
//
// Before taking a sample, the profiler checks using `dynamic_sampling_rate_should_sample()`, if it's time or not to
// sample. If it's not, it will skip sampling.
//
// Finally, as an additional optimization, there's a `dynamic_sampling_rate_get_sleep()` which, given the current
// wall-time, will return the time remaining (*there's an exception, check function) until the next sample.
//
// ---

// This is the wall-time overhead we're targeting. E.g. we target to spend no more than 2%, or 1.2 seconds per minute,
// taking profiling samples by default.
#define DEFAULT_WALL_TIME_OVERHEAD_TARGET_PERCENTAGE 2.0 // %
// See `dynamic_sampling_rate_get_sleep()` for details
#define MAX_SLEEP_TIME_NS MILLIS_AS_NS(100)
// See `dynamic_sampling_rate_after_sample()` for details
#define MAX_TIME_UNTIL_NEXT_SAMPLE_NS SECONDS_AS_NS(10)

#define EMA_SMOOTHING_FACTOR 0.2

void dynamic_sampling_rate_init(dynamic_sampling_rate_state *state) {
  atomic_init(&state->next_sample_after_monotonic_wall_time_ns, 0);
  dynamic_sampling_rate_set_overhead_target_percentage(state, DEFAULT_WALL_TIME_OVERHEAD_TARGET_PERCENTAGE);
}

void dynamic_sampling_rate_set_overhead_target_percentage(dynamic_sampling_rate_state *state, double overhead_target_percentage) {
  state->overhead_target_percentage = overhead_target_percentage;
}

void dynamic_sampling_rate_reset(dynamic_sampling_rate_state *state) {
  atomic_store(&state->next_sample_after_monotonic_wall_time_ns, 0);
  state->tick_time_ns = 0;
  state->last_check_time_ns = 0;
}

uint64_t dynamic_sampling_rate_get_sleep(dynamic_sampling_rate_state *state, long current_monotonic_wall_time_ns) {
  long next_sample_after_ns = atomic_load(&state->next_sample_after_monotonic_wall_time_ns);
  long delta_ns = next_sample_after_ns - current_monotonic_wall_time_ns;

  if (delta_ns > 0 && next_sample_after_ns > 0) {
    // We don't want to sleep for too long as the profiler may be trying to stop.
    //
    // Instead, here we sleep for at most this time. Worst case, the profiler will still try to sample before
    // `next_sample_after_monotonic_wall_time_ns`, BUT `dynamic_sampling_rate_should_sample()` will still be false
    // so we still get the intended behavior.
    return uint64_min_of(delta_ns, MAX_SLEEP_TIME_NS);
  } else {
    return 0;
  }
}

bool dynamic_sampling_rate_should_sample(dynamic_sampling_rate_state *state, long wall_time_ns_before_sample) {
  long latest_tick_time_ns = long_max_of(0, wall_time_ns_before_sample - state->last_check_time_ns);
  state->tick_time_ns = ((unsigned long) (EMA_SMOOTHING_FACTOR * latest_tick_time_ns) + ((1.0 - EMA_SMOOTHING_FACTOR) * state->tick_time_ns));
  state->last_check_time_ns = wall_time_ns_before_sample;
  return wall_time_ns_before_sample >= atomic_load(&state->next_sample_after_monotonic_wall_time_ns);
}

static void dynamic_sampling_rate_after_sample(dynamic_sampling_rate_state *state, long wall_time_ns_after_sample, uint64_t tick_time_ns, uint64_t sampling_time_ns) {
  double overhead_target = state->overhead_target_percentage;

  // The idea here is that we're targeting a maximum % of wall-time spent sampling.
  // We have 4 variables:
  // * sampling_time -> How long did we spend sampling
  // * overhead_target -> Percentage of time we want sampling_time to represent in relation to total time
  // * sleeping_time -> How long we want to delay sampling for to keep to overhead_target
  // * tick_time -> Time between sampling opportunities (0 for continuous operation, time between sampling decisions in discrete ones)
  // Thus, total_time can be understood to be sampling_time + sleeping_time + tick_time and we want to solve for sleep_time in the
  // following relation:
  //
  //   sampling_time  ----- overhead_target
  //   total_time     ------ 100%
  //
  // Which wields:
  //
  //     total_time = 100 * sampling_time / overhead_target <=>
  // <=> sleeping_time + sampling_time + tick_time  = 100 * sampling_time / overhead_target <=>
  // <=> sleeping_time = 100 * sampling_time / overhead_target - sampling_time - tick_time
  //
  // For a concrete example of continuous sampling where:
  // * overhead_target = 2%
  // * sampling_time = 1ms
  // * between_time = 0
  //
  // Then sleeping_time would wield (100 * 1ms) / 2 - 1 = 49ms
  uint64_t time_to_sleep_ns = 100.0 * sampling_time_ns / overhead_target - sampling_time_ns - tick_time_ns;

  // In case a sample took an unexpected long time (e.g. maybe a VM was paused, or a laptop was suspended), we clamp the
  // value so it doesn't get too crazy
  time_to_sleep_ns = uint64_min_of(time_to_sleep_ns, MAX_TIME_UNTIL_NEXT_SAMPLE_NS);

  atomic_store(&state->next_sample_after_monotonic_wall_time_ns, wall_time_ns_after_sample + time_to_sleep_ns);
}

void dynamic_sampling_rate_after_sample_continuous(dynamic_sampling_rate_state *state, long wall_time_ns_after_sample, uint64_t sampling_time_ns) {
  dynamic_sampling_rate_after_sample(state, wall_time_ns_after_sample, 0, sampling_time_ns);
}

void dynamic_sampling_rate_after_sample_discrete(dynamic_sampling_rate_state *state, long wall_time_ns_after_sample, uint64_t sampling_time_ns) {
  dynamic_sampling_rate_after_sample(state, wall_time_ns_after_sample, state->tick_time_ns, sampling_time_ns);
}

// ---
// Below here is boilerplate to expose the above code to Ruby so that we can test it with RSpec as usual.

VALUE _native_get_sleep(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE simulated_next_sample_after_monotonic_wall_time_ns, VALUE current_monotonic_wall_time_ns);
VALUE _native_should_sample(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE simulated_next_sample_after_monotonic_wall_time_ns, VALUE wall_time_ns_before_sample);
VALUE _native_after_sample_continuous(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE wall_time_ns_after_sample, VALUE sampling_time_ns);
VALUE _native_after_sample_discrete(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE wall_time_ns_after_sample, VALUE sampling_time_ns);

void collectors_dynamic_sampling_rate_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE dynamic_sampling_rate_module = rb_define_module_under(collectors_module, "DynamicSamplingRate");
  VALUE testing_module = rb_define_module_under(dynamic_sampling_rate_module, "Testing");

  rb_define_singleton_method(testing_module, "_native_get_sleep", _native_get_sleep, 3);
  rb_define_singleton_method(testing_module, "_native_should_sample", _native_should_sample, 3);
  rb_define_singleton_method(testing_module, "_native_after_sample_continuous", _native_after_sample_continuous, 3);
  rb_define_singleton_method(testing_module, "_native_after_sample_discrete", _native_after_sample_discrete, 3);
}

VALUE _native_get_sleep(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE simulated_next_sample_after_monotonic_wall_time_ns, VALUE current_monotonic_wall_time_ns) {
  ENFORCE_TYPE(simulated_next_sample_after_monotonic_wall_time_ns, T_FIXNUM);
  ENFORCE_TYPE(current_monotonic_wall_time_ns, T_FIXNUM);

  dynamic_sampling_rate_state state;
  dynamic_sampling_rate_init(&state);
  dynamic_sampling_rate_set_overhead_target_percentage(&state, NUM2DBL(overhead_target_percentage));
  atomic_store(&state.next_sample_after_monotonic_wall_time_ns, NUM2LONG(simulated_next_sample_after_monotonic_wall_time_ns));

  return ULL2NUM(dynamic_sampling_rate_get_sleep(&state, NUM2LONG(current_monotonic_wall_time_ns)));
}

VALUE _native_should_sample(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE simulated_next_sample_after_monotonic_wall_time_ns, VALUE wall_time_ns_before_sample) {
  ENFORCE_TYPE(simulated_next_sample_after_monotonic_wall_time_ns, T_FIXNUM);
  ENFORCE_TYPE(wall_time_ns_before_sample, T_FIXNUM);

  dynamic_sampling_rate_state state;
  dynamic_sampling_rate_init(&state);
  dynamic_sampling_rate_set_overhead_target_percentage(&state, NUM2DBL(overhead_target_percentage));
  atomic_store(&state.next_sample_after_monotonic_wall_time_ns, NUM2LONG(simulated_next_sample_after_monotonic_wall_time_ns));

  return dynamic_sampling_rate_should_sample(&state, NUM2LONG(wall_time_ns_before_sample)) ? Qtrue : Qfalse;
}

VALUE _native_after_sample_continuous(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE wall_time_ns_after_sample, VALUE sampling_time_ns) {
  ENFORCE_TYPE(wall_time_ns_after_sample, T_FIXNUM);
  ENFORCE_TYPE(sampling_time_ns, T_FIXNUM);

  dynamic_sampling_rate_state state;
  dynamic_sampling_rate_init(&state);
  dynamic_sampling_rate_set_overhead_target_percentage(&state, NUM2DBL(overhead_target_percentage));

  dynamic_sampling_rate_after_sample_continuous(&state, NUM2LONG(wall_time_ns_after_sample), NUM2ULL(sampling_time_ns));

  return ULL2NUM(atomic_load(&state.next_sample_after_monotonic_wall_time_ns));
}

VALUE _native_after_sample_discrete(DDTRACE_UNUSED VALUE self, VALUE overhead_target_percentage, VALUE wall_time_ns_after_sample, VALUE sampling_time_ns) {
  ENFORCE_TYPE(wall_time_ns_after_sample, T_FIXNUM);
  ENFORCE_TYPE(sampling_time_ns, T_FIXNUM);

  dynamic_sampling_rate_state state;
  dynamic_sampling_rate_init(&state);
  dynamic_sampling_rate_set_overhead_target_percentage(&state, NUM2DBL(overhead_target_percentage));

  dynamic_sampling_rate_after_sample_discrete(&state, NUM2LONG(wall_time_ns_after_sample), NUM2ULL(sampling_time_ns));

  return ULL2NUM(atomic_load(&state.next_sample_after_monotonic_wall_time_ns));
}
