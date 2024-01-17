require 'datadog/profiling/spec_helper'
require 'datadog/profiling'

RSpec.describe Datadog::Profiling::Collectors::Testing::DiscreteDynamicSampler do
  let(:max_overhead_target) { 2.0 }

  before do
    skip_if_profiling_not_supported(self)
    @now = Time.now.to_f
  end

  subject(:sampler) do
    sampler = described_class.new
    sampler.reset(max_overhead_target)
    sampler
  end

  def maybe_sample(now, sampling_time)
    start_ns = (now * 1e9).to_i
    end_ns = start_ns + (sampling_time * 1e9).to_i
    sampler.after_sample(end_ns) / 1e9 if sampler.should_sample(start_ns)
  end

  def simulate_load(duration_seconds:, events_per_second:, sampling_seconds:)
    start = @now
    num_events = (events_per_second.to_f * duration_seconds).to_i
    time_between_events = duration_seconds.to_f / num_events
    num_samples = 0
    total_sampling_seconds = 0
    num_events.times do
      sampling_time = maybe_sample(@now, sampling_seconds)
      unless sampling_time.nil?
        num_samples += 1
        total_sampling_seconds += sampling_time
        @now += sampling_time
      end
      @now += time_between_events
    end
    {
      sampling_ratio: num_samples.to_f / num_events,
      total_sampling_seconds: total_sampling_seconds,
      overhead: total_sampling_seconds / (@now - start),
      num_samples: num_samples,
      num_events: num_events,
    }
  end

  context 'when under a constant' do
    context 'low load' do
      it 'samples everything that comes' do
        # Max overhead of 2% over 1 second means a max of 0.02 seconds of sampling.
        # With each sample taking 0.01 seconds, we can afford to do 2 of these every second.
        # At an event rate of 1/sec we can sample all.
        stats = simulate_load(duration_seconds: 60, events_per_second: 1, sampling_seconds: 0.01)
        expect(stats[:sampling_ratio]).to eq(1)
        expect(stats[:overhead]).to be < max_overhead_target
      end
    end

    context 'moderate load' do
      it 'samples only as many samples as it can to keep to the overhead target' do
        # Max overhead of 2% over 1 second means a max of 0.02 seconds of sampling.
        # With each sample taking 0.01 seconds, we can afford to do 2 of these every second.
        # At an event rate of 8/sec we can sample 1/4 of total events.
        stats = simulate_load(duration_seconds: 60, events_per_second: 8, sampling_seconds: 0.01)
        expect(sampler.probability).to be_between(23, 27)
        expect(stats[:sampling_ratio]).to be_between(0.23, 0.27)
        expect(stats[:overhead]).to be < max_overhead_target
      end
    end

    context 'heavy load' do
      it 'will heavily restrict sampling' do
        # Max overhead of 2% over 1 second means a max of 0.02 seconds of sampling.
        # With each sample taking 0.01 seconds, we can afford to do 2 of these every second.
        # At an event rate of 100/sec we can sample 2% of total events.
        stats = simulate_load(duration_seconds: 60, events_per_second: 100, sampling_seconds: 0.01)
        expect(sampler.probability).to be_between(1, 3)
        expect(stats[:sampling_ratio]).to be_between(0.01, 0.03)
        expect(stats[:overhead]).to be < max_overhead_target
      end
    end
  end

  context 'when under a variable load' do
    context 'containing lots of short spikes' do
      it 'will readjust to decrease sampling rate' do
        # Baseline
        simulate_load(duration_seconds: 10, events_per_second: 10, sampling_seconds: 0.01)
        p_baseline = sampler.probability

        # We'll spike every 5 seconds. Sampler should have some short term memory so
        # after a spiking period it should be using a lower probability
        simulate_load(duration_seconds: 1, events_per_second: 1000, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 5, events_per_second: 10, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 1, events_per_second: 1000, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 5, events_per_second: 10, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 1, events_per_second: 1000, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 10, events_per_second: 10, sampling_seconds: 0.01)

        p_after_spikes = sampler.probability

        expect(p_after_spikes).to be < p_baseline
      end
    end

    context 'with a big spike at the beginning' do
      it "won't wait until the next sample to adjust" do
        # We'll start with a very big load at the beginning. This should move the sampler towards
        # having very low sampling probabilities (i.e. a big sampling interval). We want to validate
        # that the sampler can readjust in-between samples so it can react to load pattern changes
        # that may happen inbetween. If that weren't the case, after we go down to a very low event
        # baseline, entire minutes could pass before we even decide to sample again and realize that
        # we've been sampling nothing for a while.
        simulate_load(duration_seconds: 5, events_per_second: 100000, sampling_seconds: 0.01)
        p1 = sampler.probability
        expect(p1).to be < 0.1 # %

        # With such a low probability, our sampling skip is >1000 so if we relied on samples alone
        # for adjustment, the 10 events generated in the following 2 loads would not trigger this
        # readjustment.

        simulate_load(duration_seconds: 5, events_per_second: 1, sampling_seconds: 0.01)
        p2 = sampler.probability
        expect(p2).to be > p1

        simulate_load(duration_seconds: 5, events_per_second: 1, sampling_seconds: 0.01)
        p3 = sampler.probability
        expect(p3).to be > p2
      end
    end
  end

  context 'when sampling time worsens' do
    it 'will readjust to decrease sampling rate' do
      # Start with an initial load of 8 eps @ 0.01s sampling time should give us a sampling
      # probability of around 25% given our 2% overhead target (see similar test case above)
      stats = simulate_load(duration_seconds: 60, events_per_second: 8, sampling_seconds: 0.01)
      expect(stats[:sampling_ratio]).to be_between(0.23, 0.27)

      # However, we'll now worsen our sampling time in 2x keeping all other things equal. We
      # expect our sampling probability to halve (~12.5%)
      stats = simulate_load(duration_seconds: 60, events_per_second: 8, sampling_seconds: 0.02)
      expect(stats[:sampling_ratio]).to be_between(0.10, 0.13)
    end
  end

  context 'when sampling time improves' do
    it 'will readjust to increase sampling rate' do
      # Start with an initial load of 8 eps @ 0.01s sampling time should give us a sampling
      # probability of around 25% given our 2% overhead target (see similar test case above)
      stats = simulate_load(duration_seconds: 60, events_per_second: 8, sampling_seconds: 0.01)
      expect(stats[:sampling_ratio]).to be_between(0.23, 0.27)

      # However, we'll now improve our sampling time in 2x keeping all other things equal. We
      # expect our sampling probability to double (~50%)
      stats = simulate_load(duration_seconds: 60, events_per_second: 8, sampling_seconds: 0.005)
      expect(stats[:sampling_ratio]).to be_between(0.45, 0.55)
    end
  end

  context 'given a constant load' do
    it "the higher the target overhead, the more we'll sample" do
      # Start with an initial load of 4 eps @ 0.01s sampling time should give us a sampling
      # probability of around 50% given our 2% overhead target (see similar test case above)
      stats = simulate_load(duration_seconds: 60, events_per_second: 4, sampling_seconds: 0.01)
      expect(stats[:sampling_ratio]).to be_between(0.45, 0.55)

      # We'll now increase our overhead target to 4%
      sampler.reset(max_overhead_target * 2)

      # This should allow us to sample the entire load
      stats = simulate_load(duration_seconds: 60, events_per_second: 4, sampling_seconds: 0.01)
      expect(stats[:sampling_ratio]).to eq(1)
    end
  end
end
