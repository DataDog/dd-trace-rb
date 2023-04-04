require 'spec_helper'

require 'datadog/tracing/sampling/rate_by_key_sampler'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Sampling::RateByKeySampler do
  subject(:sampler) { described_class.new(default_key, default_rate, &resolver) }

  let(:default_key) { 'default-key' }
  # For testing purposes, never keep a span operation by default.
  # DEV: Setting this to 0 would trigger a safe guard in `RateSampler` and set it to 100% instead.
  let(:default_rate) { Float::MIN }

  let(:trace) { Datadog::Tracing::TraceOperation.new(name: 'test-trace') }
  let(:resolver) { ->(trace) { trace.name } } # Resolve +trace.name+ to the lookup key.
  let(:trace_key) { trace.name }

  describe '#sample!' do
    subject(:sample!) { sampler.sample!(trace) }

    it { is_expected.to be(false) }

    context 'with a default rate set to keep all traces' do
      let(:default_rate) { 1.0 }
      it { is_expected.to be(true) }
    end

    context 'with a sample rate associated with a key set to keep all traces' do
      before { sampler.update(trace_key, 1.0) }
      it { is_expected.to be(true) }
    end
  end

  describe '#update' do
    subject!(:update) { sampler.update(key, rate) }
    let(:key) { trace_key }
    let(:rate) { default_rate }

    let!(:sample) { sampler.sample!(trace) }

    context 'with sampling rate 100%' do
      let(:rate) { 1.0 }
      it { expect(sample).to eq(true) }

      context 'with default decision' do
        it { expect(trace.get_tag('_dd.p.dm')).to be_nil }
      end

      context 'with decision set' do
        subject!(:update) { sampler.update(key, rate, decision: decision) }
        let(:decision) { 'test decision' }

        it { expect(trace.get_tag('_dd.p.dm')).to eq(decision) }
      end
    end

    context 'with sampling rate 0%' do
      let(:rate) { Float::MIN } # DEV: Using 0 would trigger a safe guard in `RateSampler` and set it to 100% instead.
      it { expect(sample).to eq(false) }

      context 'does not set decision' do
        it { expect(trace.get_tag('_dd.p.dm')).to be_nil }
      end
    end
  end
end
