# typed: false

require 'spec_helper'

require 'datadog/tracing/sampling/rate_by_key_sampler'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Sampling::RateByKeySampler do
  subject(:sampler) { described_class.new(default_key, default_rate, &resolver) }

  let(:default_key) { 'default-key' }

  let(:trace) { Datadog::Tracing::TraceOperation.new(name: 'test-trace') }
  let(:resolver) { ->(trace) { trace.name } } # Resolve +trace.name+ to the lookup key.

  describe '#sample!' do
    subject(:sample!) { sampler.sample!(trace) }

    # For testing purposes, never keep a span operation by default.
    # DEV: Setting this to 0 would trigger a safe guard in `RateSampler` and set it to 100% instead.
    let(:default_rate) { Float::MIN }
    it { is_expected.to be(false) }

    context 'with a default rate set to keep all traces' do
      let(:default_rate) { 1.0 }
      it { is_expected.to be(true) }
    end

    context 'with a sample rate associated with a key set to keep all traces' do
      before { sampler.update('test-trace', 1.0) }
      it { is_expected.to be(true) }
    end
  end
end
