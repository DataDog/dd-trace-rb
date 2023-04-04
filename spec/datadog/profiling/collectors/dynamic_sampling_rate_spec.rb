require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/dynamic_sampling_rate'

RSpec.describe Datadog::Profiling::Collectors::DynamicSamplingRate do
  before { skip_if_profiling_not_supported(self) }

  describe 'dynamic_sampling_rate_after_sample' do
    let(:current_monotonic_wall_time_ns) { 123 }

    it 'sets the next_sample_after_monotonic_wall_time_ns based on the current timestamp and max overhead target' do
      max_overhead_target = 2.0 # WALL_TIME_OVERHEAD_TARGET_PERCENTAGE
      sampling_time_ns = 456

      # The idea here is -- if sampling_time_ns is 2% of the time we spend working, how much is the 98% we should spend
      # sleeping?
      expected_time_to_sleep = sampling_time_ns * ((100 - max_overhead_target) / max_overhead_target)

      expect(described_class::Testing._native_after_sample(current_monotonic_wall_time_ns, sampling_time_ns))
        .to be(current_monotonic_wall_time_ns + expected_time_to_sleep.to_i)
    end

    context 'when next_sample_after_monotonic_wall_time_ns would be too far in the future' do
      it 'sets the next_sample_after_monotonic_wall_time_ns to be current timestamp + MAX_TIME_UNTIL_NEXT_SAMPLE_NS' do
        max_time_until_next_sample_ns = 10_000_000_000 # MAX_TIME_UNTIL_NEXT_SAMPLE_NS
        sampling_time_ns = 60_000_000_000

        expect(described_class::Testing._native_after_sample(current_monotonic_wall_time_ns, sampling_time_ns))
          .to be(current_monotonic_wall_time_ns + max_time_until_next_sample_ns)
      end
    end
  end

  describe 'dynamic_sampling_rate_should_sample' do
    let(:next_sample_after_monotonic_wall_time_ns) { 10 }

    subject(:dynamic_sampling_rate_should_sample) do
      described_class::Testing._native_should_sample(next_sample_after_monotonic_wall_time_ns, wall_time_ns_before_sample)
    end

    context 'when wall_time_ns_before_sample is before next_sample_after_monotonic_wall_time_ns' do
      let(:wall_time_ns_before_sample) { next_sample_after_monotonic_wall_time_ns - 1 }
      it { is_expected.to be false }
    end

    context 'when wall_time_ns_before_sample is after next_sample_after_monotonic_wall_time_ns' do
      let(:wall_time_ns_before_sample) { next_sample_after_monotonic_wall_time_ns + 1 }
      it { is_expected.to be true }
    end
  end

  describe 'dynamic_sampling_rate_get_sleep' do
    let(:next_sample_after_monotonic_wall_time_ns) { 1_000_000_000 }

    subject(:dynamic_sampling_rate_get_sleep) do
      described_class::Testing._native_get_sleep(next_sample_after_monotonic_wall_time_ns, current_monotonic_wall_time_ns)
    end

    context 'when current_monotonic_wall_time_ns is before next_sample_after_monotonic_wall_time_ns' do
      context(
        'when current_monotonic_wall_time_ns is less than MAX_SLEEP_TIME_NS ' \
        'from next_sample_after_monotonic_wall_time_ns'
      ) do
        let(:current_monotonic_wall_time_ns) { next_sample_after_monotonic_wall_time_ns - 1234 }

        it 'returns the time between current_monotonic_wall_time_ns and next_sample_after_monotonic_wall_time_ns' do
          expect(dynamic_sampling_rate_get_sleep).to be 1234
        end
      end

      context(
        'when current_monotonic_wall_time_ns is more than MAX_SLEEP_TIME_NS ' \
        'from next_sample_after_monotonic_wall_time_ns'
      ) do
        let(:current_monotonic_wall_time_ns) { next_sample_after_monotonic_wall_time_ns - 123_456_789 }

        it 'returns MAX_SLEEP_TIME_NS' do
          expect(dynamic_sampling_rate_get_sleep).to be 100_000_000
        end
      end
    end

    context 'when current_monotonic_wall_time_ns is after next_sample_after_monotonic_wall_time_ns' do
      let(:current_monotonic_wall_time_ns) { next_sample_after_monotonic_wall_time_ns + 1 }
      it { is_expected.to be 0 }
    end
  end
end
