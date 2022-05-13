require 'datadog/tracing/contrib/support/spec_helper'
require 'semantic_logger'
require 'datadog/tracing/contrib/semantic_logger/instrumentation'
require 'spec/support/thread_helpers'

RSpec.describe Datadog::Tracing::Contrib::SemanticLogger::Instrumentation do
  let(:instrumented) { SemanticLogger::Logger.new('TestClass') }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :semantic_logger
    end
  end

  describe '#log' do
    subject(:log) do
      ThreadHelpers.with_leaky_thread_creation('semantic_logger') do
        instrumented.log(event)
      end
    end
    let(:event) { SemanticLogger::Log.new('test', :info).tap { |e| e.named_tags = original_tags } }
    let(:original_tags) { { original: 'tag' } }

    let(:correlation) do
      Datadog::Tracing::Correlation::Identifier.new(
        trace_id: trace_id,
        span_id: span_id,
        env: env,
        service: service,
        version: version,
      )
    end
    let(:trace_id) { 'trace_id' }
    let(:span_id) { 'span_id' }
    let(:env) { 'env' }
    let(:service) { 'service' }
    let(:version) { 'version' }

    before do
      expect(Datadog::Tracing).to receive(:correlation).and_return(correlation)
    end

    it 'merges correlation data with original options' do
      expect(SemanticLogger::Logger).to receive(:call_subscribers) do |event|
        expect(event.named_tags).to eq({ original: 'tag',
                                         dd: {
                                           env: 'env',
                                           service: 'service',
                                           span_id: 'span_id',
                                           trace_id: 'trace_id',
                                           version: 'version'
                                         },
                                         ddsource: 'ruby' })
      end

      log
    end
  end
end
