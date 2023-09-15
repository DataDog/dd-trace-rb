require 'datadog/appsec/spec_helper'
require 'datadog/appsec/sample_rate'

RSpec.describe Datadog::AppSec::SampleRate do
  subject(:sample_rate) { described_class.new(rate) }
  describe '#sample?' do
    context 'when sample rate is 0' do
      let(:rate) { 0 }

      it 'returns false' do
        expect(sample_rate.sample?).to eq false
      end
    end

    context 'when sample rate is bigger or equal to 1' do
      [1, 2].each do |value|
        let(:rate) { value }

        it 'returns true' do
          expect(sample_rate.sample?).to eq true
        end
      end
    end

    context 'when sample rate is differnt than 0 or 1' do
      let(:rate) { 0.5 }

      before do
        expect(Kernel).to receive(:rand).and_return(random)
      end

      context 'when rand returns lower value than rate' do
        let(:random) { 0.4 }

        it 'returns true' do
          expect(sample_rate.sample?).to eq true
        end
      end

      context 'when rand returns higher value than rate' do
        let(:random) { 0.6 }

        it 'returns false' do
          expect(sample_rate.sample?).to eq false
        end
      end
    end
  end
end
