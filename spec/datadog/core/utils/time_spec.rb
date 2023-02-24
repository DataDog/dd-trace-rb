require 'spec_helper'

require 'time'
require 'datadog/core/utils/time'

RSpec.describe Datadog::Core::Utils::Time do
  describe '#get_time' do
    subject(:get_time) { described_class.get_time }

    it 'returns a monotonic timestamp in float seconds' do
      is_expected.to be_a_kind_of(Float)
    end

    context 'when a unit is specified' do
      it 'returns a monotonic timestamp using that unit' do
        float_seconds_timestamp = described_class.get_time
        nanoseconds_timestamp = described_class.get_time(:nanosecond)

        expect(float_seconds_timestamp * 1_000_000_000).to be_within(10_000_000).of(nanoseconds_timestamp)
      end

      it 'returns an integer value for nanoseconds' do
        expect(described_class.get_time(:nanosecond)).to be_a_kind_of(Integer)
      end
    end
  end

  describe '#measure' do
    it { expect { |b| described_class.measure(&b) }.to yield_control }

    context 'given a block' do
      subject(:measure) { described_class.measure(&block) }

      let(:block) { proc { sleep(run_time) } }
      let(:run_time) { 0.01 }

      it do
        is_expected.to be_a_kind_of(Float)
        is_expected.to be >= run_time
      end
    end
  end

  describe '#as_utc_epoch_ns' do
    let(:time) { Time.iso8601('2021-01-01T01:02:03.405060708Z') }

    subject(:as_utc_epoch_ns) { described_class.as_utc_epoch_ns(time) }

    it 'converts a time object into nanoseconds since UTC epoch' do
      expect(as_utc_epoch_ns).to be 1609462923405060708
    end

    it 'can round trip without losing precision' do
      expect(Time.at(as_utc_epoch_ns.to_r / 1_000_000_000)).to eq time
    end

    it 'can correctly handle non-UTC time objects' do
      # same as :time above, but in a different timezone
      non_utc_time = Time.iso8601('2021-01-01T06:32:03.405060708+05:30')

      expect(as_utc_epoch_ns).to eq described_class.as_utc_epoch_ns(non_utc_time)
    end
  end
end
