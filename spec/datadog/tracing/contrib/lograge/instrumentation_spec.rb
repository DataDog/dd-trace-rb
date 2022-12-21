require 'datadog/tracing/contrib/support/spec_helper'
require 'lograge'
require 'datadog/tracing/contrib/lograge/instrumentation'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Contrib::Lograge::Instrumentation do
  let(:instrumented) { Lograge::LogSubscribers::Base.new }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :lograge
    end
  end

  describe '#custom_options' do
    subject(:custom_options) { instrumented.custom_options(event) }
    let(:event) { double(payload: { custom_payload: original_options }) }
    let(:original_options) { { original: 'option' } }

    let(:correlation) do
      Datadog::Tracing::Correlation::Identifier.new(
        trace_id: trace_id,
        span_id: span_id,
        env: env,
        service: service,
        version: version,
      )
    end
    let(:trace_id) { Datadog::Tracing::Utils.next_id }
    let(:span_id) { Datadog::Tracing::Utils.next_id }
    let(:env) { 'env' }
    let(:service) { 'service' }
    let(:version) { 'version' }

    before do
      expect(Datadog::Tracing).to receive(:correlation).and_return(correlation)
    end

    it 'merges correlation data with original options' do
      is_expected.to eq(
        { original: 'option',
          dd: {
            env: 'env',
            service: 'service',
            span_id: span_id.to_s,
            trace_id: trace_id.to_s,
            version: 'version'
          },
          ddsource: 'ruby' }
      )
    end
  end
end
