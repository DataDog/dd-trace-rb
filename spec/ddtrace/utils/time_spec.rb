require 'spec_helper'

require 'ddtrace/utils/time'

RSpec.describe Datadog::Utils::Time do
  describe '#get_time' do
    subject(:get_time) { described_class.get_time }
    it { is_expected.to be_a_kind_of(Float) }
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
