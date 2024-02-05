require 'datadog/profiling/spec_helper'
require 'datadog/profiling'

RSpec.describe 'Datadog::Profiling::Collectors::DiscreteDynamicSampler' do
  let(:max_overhead_target) { 2.0 }

  before do
    skip_if_profiling_not_supported(self)
    @now = Time.now.to_f
  end

  subject!(:sampler) do
    sampler = Datadog::Profiling::Collectors::DiscreteDynamicSampler::Testing::Sampler.new
    update_overhead_target(max_overhead_target, sampler)
    sampler
  end

  def maybe_sample(sampling_seconds:)
    start_ns = (@now * 1e9).to_i
    end_ns = start_ns + (sampling_seconds * 1e9).to_i
    sampler._native_after_sample(end_ns) / 1e9 if sampler._native_should_sample(start_ns)
  end

  def simulate_load(duration_seconds:, events_per_second:, sampling_seconds:)
    start = @now
    num_events = (events_per_second.to_f * duration_seconds).to_i
    time_between_events = duration_seconds.to_f / num_events
    num_samples = 0
    total_sampling_seconds = 0
    num_events.times do
      # We update time at the beginning on purpose to force the last event to
      # occur at the end of the specified duration window. In other words, we
      # consciously go with end-aligned allocations in these simulated loads
      # so that it's easier to force
      @now += time_between_events
      sampling_time = maybe_sample(sampling_seconds: sampling_seconds)
      next if sampling_time.nil?

      num_samples += 1
      total_sampling_seconds += sampling_time
      @now += sampling_time
    end
    {
      sampling_ratio: num_samples.to_f / num_events,
      total_sampling_seconds: total_sampling_seconds,
      overhead: total_sampling_seconds / (@now - start),
      num_samples: num_samples,
      num_events: num_events,
    }
  end

  def update_overhead_target(new_overhead_target, sampler_instance = sampler)
    sampler_instance._native_set_overhead_target_percentage(new_overhead_target, (@now * 1e9).to_i)
  end

  def sampler_current_probability
    sampler._native_state_snapshot[:sampling_probability]
  end

  def sampler_current_events_per_sec
    sampler._native_state_snapshot[:events_per_sec]
  end

  context 'when under a constant' do
    let(:stats) do
      # Warm things up a little to overcome the hardcoded starting parameters
      simulate_load(duration_seconds: 5, events_per_second: events_per_second, sampling_seconds: 0.01)
      # Actual stat window we care about
      simulate_load(duration_seconds: 60, events_per_second: events_per_second, sampling_seconds: 0.01)
    end

    context 'low load' do
      let(:events_per_second) { 1 }

      it 'samples everything that comes' do
        # Max overhead of 2% over 1 second means a max of 0.02 seconds of sampling.
        # With each sample taking 0.01 seconds, we can afford to do 2 of these every second.
        # At an event rate of 1/sec we can sample all.
        expect(stats[:sampling_ratio]).to eq(1)
        expect(stats[:overhead]).to be < max_overhead_target
        expect(sampler_current_probability).to eq(100)
      end
    end

    context 'moderate load' do
      let(:events_per_second) { 8 }

      it 'samples only as many samples as it can to keep to the overhead target' do
        # Max overhead of 2% over 1 second means a max of 0.02 seconds of sampling.
        # With each sample taking 0.01 seconds, we can afford to do 2 of these every second.
        # At an event rate of 8/sec we can sample 1/4 of total events.
        expect(stats[:sampling_ratio]).to be_between(0.23, 0.27)
        expect(stats[:overhead]).to be < max_overhead_target
        expect(sampler_current_probability).to be_between(23, 27)
      end
    end

    context 'heavy load' do
      let(:events_per_second) { 100 }

      it 'will heavily restrict sampling' do
        # Max overhead of 2% over 1 second means a max of 0.02 seconds of sampling.
        # With each sample taking 0.01 seconds, we can afford to do 2 of these every second.
        # At an event rate of 100/sec we can sample 2% of total events.
        expect(stats[:sampling_ratio]).to be_between(0.01, 0.03)
        expect(stats[:overhead]).to be < max_overhead_target
        expect(sampler_current_probability).to be_between(1, 3)
      end
    end
  end

  context 'when under a variable load' do
    context 'containing lots of short spikes' do
      it 'will readjust to decrease sampling rate' do
        # Baseline
        simulate_load(duration_seconds: 10, events_per_second: 10, sampling_seconds: 0.01)
        p_baseline = sampler_current_probability

        # We'll spike every 5 seconds. Sampler should have some short term memory so
        # after a spiking period it should be using a lower probability
        simulate_load(duration_seconds: 1, events_per_second: 1000, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 5, events_per_second: 10, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 1, events_per_second: 1000, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 5, events_per_second: 10, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 1, events_per_second: 1000, sampling_seconds: 0.01)
        simulate_load(duration_seconds: 10, events_per_second: 10, sampling_seconds: 0.01)

        p_after_spikes = sampler_current_probability

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
        simulate_load(duration_seconds: 5, events_per_second: 10000, sampling_seconds: 0.01)
        p1 = sampler_current_probability
        expect(p1).to be < 0.1 # %

        # With such a low probability, our sampling skip is >1000 so if we relied on samples alone
        # for adjustment, the events generated in each of the following loads would not be enough to
        # trigger this readjustment. We expect that continuous adjustment slowly brings probabilities
        # up and eventually we can sample again within some reasonable amount of settings (15 secs
        last_p = p1
        samples = 0
        5.times do
          stats = simulate_load(duration_seconds: 2, events_per_second: 1, sampling_seconds: 0.01)
          current_p = sampler_current_probability
          expect(current_p).to be > last_p

          last_p = current_p

          samples += stats[:num_samples]
        end
        expect(samples).to be_between(1, 3)

        # After 10 seconds of 1 event/sec at 0.01 sampling time (fully inside our overhead target),
        # we should be back to a relatively high probability
        expect(sampler_current_probability).to be > 30 # %
      end
    end

    context 'with a big spike that fits within an adjustment window' do
      it 'will readjust preemptively with smaller windows to prevent sampling overload' do
        # Start with a very small constant load during a long time. So low in fact that we'll
        # decide to sample everything
        simulate_load(duration_seconds: 60, events_per_second: 1, sampling_seconds: 0.0001)
        expect(sampler_current_probability).to eq(100) # %
        expect(sampler_current_events_per_sec).to be_within(0.1).of(1)

        # Now lets do a big event spike over half a second. This is within an adjustment
        # window so in theory we should only react after it occurred. But if this happened
        # we'd sample all of these events. Instead, we expect our sampler to preempt
        # adjustments with smaller windows to try and contain the deluge
        stats = simulate_load(duration_seconds: 0.5, events_per_second: 5000, sampling_seconds: 0.0001)
        expect(stats[:num_samples]).to be < 1000
        expect(sampler_current_probability).to be < 25 # %
        # We also expect this brief spike to not have led us to completely forget the recent past
        # where we had very little eventing taking place so events_per_sec for instance should
        # not be too close to 5000.
        expect(sampler_current_events_per_sec).to be < 1250
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
      # Warm-up to overcome initial hardcoded window
      simulate_load(duration_seconds: 5, events_per_second: 4, sampling_seconds: 0.01)
      # Start with an initial load of 4 eps @ 0.01s sampling time should give us a sampling
      # probability of around 50% given our 2% overhead target (see similar test case above)
      stats = simulate_load(duration_seconds: 60, events_per_second: 4, sampling_seconds: 0.01)
      expect(stats[:sampling_ratio]).to be_between(0.45, 0.55)

      # We'll now increase our overhead target to 4%
      update_overhead_target(max_overhead_target * 2)

      # Warm-up to overcome initial hardcoded window
      simulate_load(duration_seconds: 5, events_per_second: 4, sampling_seconds: 0.01)
      # This should allow us to sample the entire load
      stats = simulate_load(duration_seconds: 60, events_per_second: 4, sampling_seconds: 0.01)
      expect(stats[:sampling_ratio]).to eq(1)
    end
  end

  it 'disables sampling for next window if sampling overhead is deemed extremely high but relaxes over time' do
    # Max overhead of 2% over 1 seconds means a max of 0.02 seconds of sampling each second. If each
    # of our samples takes 0.08 seconds, there's no way for us to sample and meet the target
    # so probability and intervals must go down to 0.
    # This will trigger a readjustment because duration >= readjust_window
    simulate_load(duration_seconds: 1, events_per_second: 4, sampling_seconds: 0.08)
    expect(sampler_current_probability).to eq(0)

    # Since that initial readjustment set probability to 0, all events in the next window will be ignored but
    # ideally we should slowly relax this over time otherwise probability = 0 would be a terminal state (if we
    # never sample again, we'll be "stuck" with the same sampling overhead view that determined probability = 0
    # in the first place since no new sampling data came in). Because of that, over a large enough window, we
    # should get some "are things still as bad as before?" probing samples.
    #
    # Question is: how long do we have to wait for probing samples? Intuitively, we need to build enough budget over
    # time for us to be able to take that probing hit assuming things remain the same. Each adjustment window
    # with no sampling activity earns us 0.02 seconds of budget. Therefore we need 4 of these to go by before
    # we see the next probing sample.
    stats = simulate_load(duration_seconds: 3, events_per_second: 4, sampling_seconds: 2)
    expect(stats[:num_samples]).to eq(0)
    stats = simulate_load(duration_seconds: 1, events_per_second: 4, sampling_seconds: 2)
    expect(stats[:num_samples]).to eq(1)
  end
end
