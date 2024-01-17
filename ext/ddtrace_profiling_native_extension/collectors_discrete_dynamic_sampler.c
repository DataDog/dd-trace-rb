#include "collectors_discrete_dynamic_sampler.h"

#include <ruby.h>
#include "helpers.h"
#include "time_helpers.h"
#include "ruby_helpers.h"

#define BASE_OVERHEAD_PCT 1.0

#define ADJUSTMENT_WINDOW_NS SECONDS_AS_NS(1)

#define EMA_SMOOTHING_FACTOR 0.6
#define EXP_MOVING_AVERAGE(last, avg) (1-EMA_SMOOTHING_FACTOR) * avg + EMA_SMOOTHING_FACTOR * last

struct discrete_dynamic_sampler {
  // --- Config ---
  // Id of this sampler for debug logs.
  const char *id;
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
  size_t sampling_interval;

  // -- Sampling State --
  // How many events have we seen since we last decided to sample.
  size_t events_since_last_sample;
  // Captures the time at which the last true-returning call to should_sample happened.
  // This is used in after_sample to understand the total sample time.
  long sample_start_time_ns;

  // -- Adjustment State --
  // Time at which we last readjust our sampling parameters.
  long last_readjust_time_ns;
  // How many events have we seen since the last readjustment.
  size_t events_since_last_readjustment;
  // How many samples have we seen since the last readjustment.
  size_t samples_since_last_readjustment;
  // How much time have we spent sampling since the last readjustment.
  long sampling_time_since_last_readjustment_ns;
  // A negative number that we add to target_overhead to serve as extra padding to
  // try and mitigate observed overshooting of max sampling time.
  double target_overhead_adjustment;
};

discrete_dynamic_sampler* discrete_dynamic_sampler_new(const char *id) {
  discrete_dynamic_sampler *sampler = ruby_xcalloc(1, sizeof(discrete_dynamic_sampler));
  sampler->id = id;
  discrete_dynamic_sampler_reset(sampler, BASE_OVERHEAD_PCT);
  return sampler;
}

void discrete_dynamic_sampler_reset(discrete_dynamic_sampler *sampler, double target_overhead) {
  if (target_overhead <= 0 || target_overhead > 100) {
    rb_raise(rb_eArgError, "Target overhead must be a double between ]0,100] was %f", target_overhead);
  }
  const char *id = sampler->id;
  (*sampler) = (discrete_dynamic_sampler) {
    .id = id,
    .target_overhead = target_overhead,
  };
}

void discrete_dynamic_sampler_free(discrete_dynamic_sampler *sampler) {
  ruby_xfree(sampler);
}

static void maybe_readjust(discrete_dynamic_sampler *sampler, long now);

static bool _discrete_dynamic_sampler_should_sample(discrete_dynamic_sampler *sampler, long now_ns) {
  // For efficiency reasons we don't do true random sampling but rather systematic
  // sampling following a sample interval/skip. This can be biased and hide patterns
  // but the dynamic interval and rather indeterministic pattern of allocations in
  // most real applications should help reduce the bias impact.
  sampler->events_since_last_sample++;
  sampler->events_since_last_readjustment++;
  bool should_sample = sampler->events_since_last_sample >= sampler->sampling_interval;

  // check if we should readjust our sampler after this event
  maybe_readjust(sampler, now_ns);

  if (should_sample) {
    sampler->sample_start_time_ns = now_ns;
  }

  return should_sample;
}

bool discrete_dynamic_sampler_should_sample(discrete_dynamic_sampler *sampler) {
  long now = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);
  return _discrete_dynamic_sampler_should_sample(sampler, now);
}

static long _discrete_dynamic_sampler_after_sample(discrete_dynamic_sampler *sampler, long now_ns) {
  long last_sampling_time_ns = sampler->sample_start_time_ns == 0 ? 0 : long_max_of(0, now_ns - sampler->sample_start_time_ns);
  sampler->samples_since_last_readjustment++;
  sampler->sampling_time_since_last_readjustment_ns += last_sampling_time_ns;
  sampler->events_since_last_sample = 0;

  // check if we should readjust our sampler after this sample
  maybe_readjust(sampler, now_ns);

  return last_sampling_time_ns;
}

long discrete_dynamic_sampler_after_sample(discrete_dynamic_sampler *sampler) {
  long now = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);
  return _discrete_dynamic_sampler_after_sample(sampler, now);
}

double discrete_dynamic_sampler_event_rate(discrete_dynamic_sampler *sampler) {
  return sampler->events_per_ns * 1e9;
}

double discrete_dynamic_sampler_probability(discrete_dynamic_sampler *sampler) {
  return sampler->sampling_probability * 100.;
}

long discrete_dynamic_sampler_sampling_time_ns(discrete_dynamic_sampler *sampler) {
  return sampler->sampling_time_ns;
}

size_t discrete_dynamic_sampler_events_since_last_sample(discrete_dynamic_sampler *sampler) {
  return sampler->events_since_last_sample;
}

double discrete_dynamic_sampler_target_overhead_adjustment(discrete_dynamic_sampler *sampler) {
  return sampler->target_overhead_adjustment * 100.;
}

static void maybe_readjust(discrete_dynamic_sampler *sampler, long now) {
  long window_time_ns = sampler->last_readjust_time_ns == 0 ? ADJUSTMENT_WINDOW_NS : now - sampler->last_readjust_time_ns;

  if (window_time_ns < ADJUSTMENT_WINDOW_NS) {
    // not enough time has passed to perform a readjustment
    return;
  }

  // If we got this far, lets recalculate our sampling params based on new observations

  // Update our running average of events/sec with latest observation
  sampler->events_per_ns = EXP_MOVING_AVERAGE((double) sampler->events_since_last_readjustment / window_time_ns, sampler->events_per_ns);

  // Update our running average of sampling time for a specific event
  long sampling_window_time_ns = sampler->sampling_time_since_last_readjustment_ns;
  if (sampler->samples_since_last_readjustment > 0) {
    long avg_sampling_time_in_window_ns = sampler->samples_since_last_readjustment == 0 ? 0 : sampling_window_time_ns / sampler->samples_since_last_readjustment;
    sampler->sampling_time_ns = EXP_MOVING_AVERAGE(avg_sampling_time_in_window_ns, sampler->sampling_time_ns);
  }

  // Are we meeting our target in practice? If we're consistently overshooting our estimate due to non-uniform allocation patterns lets
  // adjust our overhead target.
  long reference_target_sampling_time_ns = window_time_ns * (sampler->target_overhead / 100.);
  long sampling_overshoot_time_ns = sampler->sampling_time_since_last_readjustment_ns - reference_target_sampling_time_ns;
  double last_target_overhead_adjustment = double_max_of(-sampler->target_overhead, double_min_of(0, -sampling_overshoot_time_ns * 100. / window_time_ns));
  sampler->target_overhead_adjustment = EXP_MOVING_AVERAGE(last_target_overhead_adjustment, sampler->target_overhead_adjustment);

  // Apply our overhead adjustment to figure out our real targets for this readjustment.
  double target_overhead = sampler->target_overhead + sampler->target_overhead_adjustment;
  long target_sampling_time_ns = window_time_ns * (target_overhead / 100.);

  // Recalculate target sampling probability so that the following 2 hold:
  // * window_time_ns = working_window_time_ns + sampling_window_time_ns
  //       │                     │                        │
  //       │                     │                        └ how much time is spent sampling
  //       │                     └── how much time is spent doing actual app stuff
  //       └── total (wall) time in this adjustment window
  // * sampling_window_time_ns <= window_time_ns * target_overhead / 100
  //
  // Note that
  //
  //   sampling_window_time_ns = samples_in_window * sampling_time_ns =
  //                                                ┌─ assuming no events will be emitted during sampling
  //                                                │
  //                           = events_per_ns * working_window_time_ns * sampling_probability * sampling_time_ns
  //
  // Re-ordering for sampling_probability and solving for the upper-bound of sampling_window_time_ns:
  //
  //   sampling_window_time_ns = window_time_ns * target_overhead / 100
  //   sampling_probability = window_time_ns * target_overhead / 100 / (events_per_ns * working_window_time_ns * sampling_time_ns) =
  //
  // Which you can intuitively understand as:
  //
  //   sampling_probability = max_allowed_time_for_sampling_ns / time_to_sample_all_events_ns
  //
  // As a quick sanity check:
  // * If app is eventing very little or we're sampling very fast, so that time_to_sample_all_events_ns < max_allowed_time_for_sampling_ns
  //   then probability will be > 1 (but we should clamp to 1 since probabilities higher than 1 don't make sense).
  // * If app is eventing a lot or our sampling overhead is big, then as time_to_sample_all_events_ns grows, sampling_probability will
  //   tend to 0.
  long working_window_time_ns = window_time_ns - sampling_window_time_ns;
  long max_allowed_time_for_sampling_ns = target_sampling_time_ns;
  long time_to_sample_all_events_ns = sampler->events_per_ns * working_window_time_ns * sampler->sampling_time_ns;
  sampler->sampling_probability = time_to_sample_all_events_ns == 0 ? 1. :
    double_min_of(1., (double) max_allowed_time_for_sampling_ns / time_to_sample_all_events_ns);

  // Doing true random selection would involve "tossing a coin" on every allocation. Lets do systematic sampling instead so that our
  // sampling decision can rely solely on a sampling skip/interval (i.e. more efficient).
  //
  //   sampling_interval = events / samples =
  //                     = event_rate * working_window_time_ns / (event_rate * working_window_time_ns * sampling_probability)
  //                     = 1 / sampling_probability
  //
  // NOTE: The sampling interval has to be an integer since we're dealing with discrete events here. This means that there'll be
  //       a loss of precision (and thus control) when adjusting between probabilities that lead to non-integer granularity
  //       changes (e.g. probabilities in the range of ]50%, 100%[ which map to intervals in the range of ]1, 2[). Our approach
  //       when the sampling interval is a non-integer is to ceil it (i.e. we'll always choose to sample less often).
  sampler->sampling_interval = ceil(1.0 / sampler->sampling_probability);

  #ifdef DD_DEBUG
    double allocs_in_60s = sampler->events_per_ns * 1e9 * 60;
    double samples_in_60s = allocs_in_60s * sampler->sampling_probability;
    double expected_total_sampling_time_in_60s =
      samples_in_60s * sampler->sampling_time_ns / 1e9;
    double real_total_sampling_time_in_60s = sampling_window_time_ns / 1e9 * 60 / (window_time_ns / 1e9);

    fprintf(stderr, "[dds.%s] readjusting...\n", sampler->id);
    fprintf(stderr, "samples_since_last_readjustment=%ld\n", sampler->samples_since_last_readjustment);
    fprintf(stderr, "window_time=%ld\n", window_time_ns);
    fprintf(stderr, "events_per_sec=%f\n", sampler->events_per_ns * 1e9);
    fprintf(stderr, "sampling_time=%ld\n", sampler->sampling_time_ns);
    fprintf(stderr, "sampling_window_time=%ld\n", sampling_window_time_ns);
    fprintf(stderr, "sampling_overshoot_time=%ld\n", sampling_overshoot_time_ns);
    fprintf(stderr, "working_window_time=%ld\n", working_window_time_ns);
    fprintf(stderr, "sampling_interval=%zu\n", sampler->sampling_interval);
    fprintf(stderr, "sampling_probability=%f\n", sampler->sampling_probability);
    fprintf(stderr, "expected allocs in 60s=%f\n", allocs_in_60s);
    fprintf(stderr, "expected samples in 60s=%f\n", samples_in_60s);
    fprintf(stderr, "expected sampling time in 60s=%f (previous real=%f)\n", expected_total_sampling_time_in_60s, real_total_sampling_time_in_60s);
    fprintf(stderr, "target_overhead_adjustment=%f\n", sampler->target_overhead_adjustment);
    fprintf(stderr, "expected max overhead in 60s=%f\n", target_overhead / 100.0 * 60);
    fprintf(stderr, "-------\n");
  #endif

  sampler->events_since_last_readjustment = 0;
  sampler->samples_since_last_readjustment = 0;
  sampler->sampling_time_since_last_readjustment_ns = 0;
  sampler->last_readjust_time_ns = now;
}

// ---
// Below here is boilerplate to expose the above code to Ruby so that we can test it with RSpec as usual.

static VALUE _native_new(VALUE klass);
static VALUE _native_reset(VALUE self, VALUE target_overhead);
static VALUE _native_should_sample(VALUE self, VALUE now);
static VALUE _native_after_sample(VALUE self, VALUE now);
static VALUE _native_probability(VALUE self);

void collectors_discrete_dynamic_sampler_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE testing_module = rb_define_module_under(collectors_module, "Testing");
  VALUE sampler_class = rb_define_class_under(testing_module, "DiscreteDynamicSampler", rb_cObject);

  rb_define_alloc_func(sampler_class, _native_new);

  rb_define_method(sampler_class, "reset", _native_reset, 1);
  rb_define_method(sampler_class, "should_sample", _native_should_sample, 1);
  rb_define_method(sampler_class, "after_sample", _native_after_sample, 1);
  rb_define_method(sampler_class, "probability", _native_probability, 0);
}

static const rb_data_type_t sampler_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::DiscreteDynamicSampler::Testing::Sampler",
  .function = {
    .dfree = RUBY_DEFAULT_FREE,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  discrete_dynamic_sampler *sampler = discrete_dynamic_sampler_new("test sampler");

  return TypedData_Wrap_Struct(klass, &sampler_typed_data, sampler);
}

static VALUE _native_reset(
  VALUE sampler_instance,
  VALUE target_overhead
) {
  ENFORCE_TYPE(target_overhead, T_FLOAT);

  discrete_dynamic_sampler *sampler;
  TypedData_Get_Struct(sampler_instance, discrete_dynamic_sampler, &sampler_typed_data, sampler);

  discrete_dynamic_sampler_reset(sampler, NUM2DBL(target_overhead));
  return Qtrue;
}

VALUE _native_should_sample(VALUE sampler_instance, VALUE now_ns) {
  ENFORCE_TYPE(now_ns, T_FIXNUM);

  discrete_dynamic_sampler *sampler;
  TypedData_Get_Struct(sampler_instance, discrete_dynamic_sampler, &sampler_typed_data, sampler);

  return _discrete_dynamic_sampler_should_sample(sampler, NUM2LONG(now_ns)) ? Qtrue : Qfalse;
}

VALUE _native_after_sample(VALUE sampler_instance, VALUE now_ns) {
  ENFORCE_TYPE(now_ns, T_FIXNUM);

  discrete_dynamic_sampler *sampler;
  TypedData_Get_Struct(sampler_instance, discrete_dynamic_sampler, &sampler_typed_data, sampler);

  return LONG2NUM(_discrete_dynamic_sampler_after_sample(sampler, NUM2LONG(now_ns)));
}

VALUE _native_probability(VALUE sampler_instance) {
  discrete_dynamic_sampler *sampler;
  TypedData_Get_Struct(sampler_instance, discrete_dynamic_sampler, &sampler_typed_data, sampler);

  return DBL2NUM(discrete_dynamic_sampler_probability(sampler));
}
