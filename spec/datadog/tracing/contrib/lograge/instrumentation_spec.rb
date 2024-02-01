require 'datadog/tracing/contrib/support/spec_helper'
require 'lograge'
require 'datadog/tracing/contrib/lograge/instrumentation'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Contrib::Lograge::Instrumentation do
  let(:instrumented) { Lograge::LogSubscribers::Base.new }

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
    let(:trace_id) { Datadog::Tracing::Utils::TraceId.next_id }
    let(:span_id) { Datadog::Tracing::Utils.next_id }
    let(:env) { 'env' }
    let(:service) { 'service' }
    let(:version) { 'version' }

    before do
      allow(Datadog::Tracing).to receive(:correlation).and_return(correlation)
    end

    after do
      Datadog.configuration.tracing.reset!
      Datadog.configuration.tracing[:lograge].reset_options!
    end

    context 'when log injection and lograge both enabled' do
      before do
        Datadog.configure do |c|
          c.tracing.log_injection = true
          c.tracing.instrument :lograge
        end
      end

      it 'merges correlation data with original options' do
        is_expected.to eq(
          { original: 'option',
            dd: {
              env: 'env',
              service: 'service',
              span_id: span_id.to_s,
              trace_id: low_order_trace_id(trace_id).to_s,
              version: 'version'
            },
            ddsource: 'ruby' }
        )
      end
    end

    context 'when log injection disabled' do
      before do
        Datadog.configure do |c|
          c.tracing.log_injection = false
          c.tracing.instrument :lograge
        end
      end

      it 'returns the original options' do
        is_expected.to eq({ original: 'option' })
      end
    end

    context 'when lograge disabled' do
      before do
        Datadog.configure do |c|
          c.tracing.log_injection = true
          c.tracing.instrument :lograge, enabled: false
        end
      end

      it 'returns the original options' do
        is_expected.to eq({ original: 'option' })
      end
    end
  end
end
