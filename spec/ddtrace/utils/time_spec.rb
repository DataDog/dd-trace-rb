# typed: false
require 'spec_helper'

require 'ddtrace/utils/time'

RSpec.describe Datadog::Utils::Time do
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
end
