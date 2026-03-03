require 'spec_helper'
require 'datadog/appsec/counter_sampler'

RSpec.describe Datadog::AppSec::CounterSampler do
  describe '#sample?' do
    subject(:sampler) { described_class.new(0.5) }

    context 'when called consecutively' do
      it 'increments counter on each call' do
        expect(sampler.sample?).to be(false)
        expect(sampler.sample?).to be(true)
        expect(sampler.sample?).to be(false)
        expect(sampler.sample?).to be(true)
        expect(sampler.sample?).to be(true)
        expect(sampler.sample?).to be(false)
      end
    end

    context 'when two separate samplers created' do
      let(:sampler_2) { described_class.new(0.5) }

      it 'counts independently' do
        expect(sampler.sample?).to eq(sampler_2.sample?)
        expect(sampler.sample?).to eq(sampler_2.sample?)
        expect(sampler.sample?).to eq(sampler_2.sample?)
      end
    end
  end
end
