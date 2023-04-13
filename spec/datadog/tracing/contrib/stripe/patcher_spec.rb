require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'stripe'
require 'datadog/tracing/contrib/stripe/patcher'

RSpec.describe Datadog::Tracing::Contrib::Stripe::Patcher do
  describe '.patch' do
    it 'adds a request_begin subscriber to Stripe::Instrumentation' do
      described_class.patch

      expect(Stripe::Instrumentation.send(:subscribers)[:request_begin].keys).to include(:datadog_tracing)
    end

    it 'adds a request_end subscriber to Stripe::Instrumentation' do
      described_class.patch

      expect(Stripe::Instrumentation.send(:subscribers)[:request_end].keys).to include(:datadog_tracing)
    end
  end
end
