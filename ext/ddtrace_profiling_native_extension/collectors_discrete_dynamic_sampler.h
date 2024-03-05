#pragma once

#include <stdbool.h>
#include <stddef.h>

#include <ruby.h>

// A sampler that will sample discrete events based on the overhead of their
// sampling.
//
// NOTE: For performance reasons, this sampler does systematic sampling via
//       sampling intervals/skips that are dynamically adjusted over time.
//       It will not perform truly random sampling by "throwing a coin" at
//       every event and is thus, in theory, susceptible to some pattern
//       biases. In practice, the dynamic readjustment of sampling interval
//       and randomized starting point should help with avoiding heavy biases.
typedef struct discrete_dynamic_sampler {
  // --- Config ---
  // Name of this sampler for debug logs.
  const char *debug_name;
  // Value in the range ]0, 100] representing the % of time we're willing to dedicate
  // to sampling.
  double target_overhead;

  // -- Reference State ---
  // Moving average of how many events per ns we saw over the recent past.
  double events_per_ns;
  // Moving average of the sampling time of each individual event.
  long sampling_time_ns;
  // Sampling probability being applied by this sampler.
  double sampling_probability;
  // Sampling interval/skip that drives the systematic sampling done by this sampler.
  // NOTE: This is an inverted view of the probability.
  // NOTE: A value of 0 works as +inf, effectively disabling sampling (to align with probability=0)
  unsigned long sampling_interval;
  // Max allowed value for an individual sampling time measurement.
  long max_sampling_time_ns;

  // -- Sampling State --
  // How many events have we seen since we last decided to sample.
  unsigned long events_since_last_sample;
  // Captures the time at which the last true-returning call to should_sample happened.
  // This is used in after_sample to understand the total sample time.
  long sample_start_time_ns;

  // -- Adjustment State --
  // Has this sampler already ran for at least one complete adjustment window?
  bool has_completed_full_adjustment_window;
  // Time at which we last readjust our sampling parameters.
  long last_readjust_time_ns;
  // How many events have we seen since the last readjustment.
  unsigned long events_since_last_readjustment;
  // How many samples have we seen since the last readjustment.
  unsigned long samples_since_last_readjustment;
  // How much time have we spent sampling since the last readjustment.
  unsigned long sampling_time_since_last_readjustment_ns;
  // A negative number that we add to target_overhead to serve as extra padding to
  // try and mitigate observed overshooting of max sampling time.
  double target_overhead_adjustment;

  // -- Interesting stats --
  unsigned long sampling_time_clamps;
} discrete_dynamic_sampler;


// Init a new sampler with sane defaults.
void discrete_dynamic_sampler_init(discrete_dynamic_sampler *sampler, const char *debug_name, long now_ns);

// Reset a sampler, clearing all stored state.
void discrete_dynamic_sampler_reset(discrete_dynamic_sampler *sampler, long now_ns);

// Sets a new target_overhead for the provided sampler, resetting it in the process.
// @param target_overhead A double representing the percentage of total time we are
//        willing to use as overhead for the resulting sampling. Values are expected
//        to be in the range ]0.0, 100.0].
void discrete_dynamic_sampler_set_overhead_target_percentage(discrete_dynamic_sampler *sampler, double target_overhead, long now_ns);

// Make a sampling decision.
//
// @return True if the event associated with this decision should be sampled, false
//         otherwise.
//
// NOTE: If true is returned we implicitly assume the start of a sampling operation
//       and it is expected that a follow-up after_sample call is issued.
bool discrete_dynamic_sampler_should_sample(discrete_dynamic_sampler *sampler, long now_ns);

// Signal the end of a sampling operation.
//
// @return Sampling time in nanoseconds for the sample operation we just finished.
long discrete_dynamic_sampler_after_sample(discrete_dynamic_sampler *sampler, long now_ns);

// Retrieve the current sampling probability ([0.0, 100.0]) being applied by this sampler.
double discrete_dynamic_sampler_probability(discrete_dynamic_sampler *sampler);

// Retrieve the current number of events seen since last sample.
unsigned long discrete_dynamic_sampler_events_since_last_sample(discrete_dynamic_sampler *sampler);

// Return a Ruby hash containing a snapshot of this sampler's interesting state at calling time.
// WARN: This allocates in the Ruby VM and therefore should not be called without the
//       VM lock or during GC.
VALUE discrete_dynamic_sampler_state_snapshot(discrete_dynamic_sampler *sampler);
