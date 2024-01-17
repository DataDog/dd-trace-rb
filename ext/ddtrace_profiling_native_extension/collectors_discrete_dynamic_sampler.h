#pragma once

#include <stdbool.h>
#include <stddef.h>

// A sampler that will sample discrete events based on the overhead of their
// sampling.
//
// NOTE: For performance reasons, this sampler does systematic sampling via
//       sampling intervals/skips that are dynamically adjusted over time.
//       It will not perform truly random sampling by "throwing a coin" at
//       every event and is thus, in theory, susceptible to some pattern
//       biases. In practice, the dynamic readjustment of sampling interval
//       and randomized starting point should help with avoiding heavy biases.
typedef struct discrete_dynamic_sampler discrete_dynamic_sampler;

// Create a new sampler with sane defaults.
discrete_dynamic_sampler* discrete_dynamic_sampler_new(const char *id);

// Reset a sampler, clearing all stored state and providing a target overhead.
// @param target_overhead A double representing the percentage of total time we are
//        willing to use as overhead for the resulting sampling. Values are expected
//        to be in the range ]0.0, 100.0].
void discrete_dynamic_sampler_reset(discrete_dynamic_sampler *sampler, double target_overhead);

// Free a previously initialized sampler.
void discrete_dynamic_sampler_free(discrete_dynamic_sampler *sampler);

// Make a sampling decision.
//
// @return True if the event associated with this decision should be sampled, false
//         otherwise.
//
// NOTE: If true is returned we implicitly assume the start of a sampling operation
//       and it is expected that a follow-up after_sample call is issued.
bool discrete_dynamic_sampler_should_sample(discrete_dynamic_sampler *sampler);

// Signal the end of a sampling operation.
//
// @return Sampling time in nanoseconds for the sample operation we just finished.
long discrete_dynamic_sampler_after_sample(discrete_dynamic_sampler *sampler);

// Retrieve the current event rate as witnessed by the discrete sampler.
//
// NOTE: This is a rolling average of the event rate over the recent past.
double discrete_dynamic_sampler_event_rate(discrete_dynamic_sampler *sampler);

// Retrieve the current sampling probability ([0.0, 100.0]) being applied by this sampler.
double discrete_dynamic_sampler_probability(discrete_dynamic_sampler *sampler);

// Retrieve the current sampling time for an individual event in nanoseconds.
//
// NOTE: This is a rolling average of the event sampling time over the recent past.
long discrete_dynamic_sampler_sampling_time_ns(discrete_dynamic_sampler *sampler);

// Retrieve the current number of events seen since last sample.
size_t discrete_dynamic_sampler_events_since_last_sample(discrete_dynamic_sampler *sampler);

// Retrieve the target overhead adjustment applied by this sampler.
//
// If a sampler sees itself constantly overshooting the configured target overhead, it
// will automatically adjust that target down to add more padding, thus acting more
// pessimistic and making it easier to stay within the desired target.
//
// NOTE: This will necessarily be a number in the range [-target_overhead, 0]. The
//       sampler will never adjust itself to go over the configured target. The
//       real overhead target is the sum of the configured target with this adjustment.
double discrete_dynamic_sampler_target_overhead_adjustment(discrete_dynamic_sampler *sampler);
