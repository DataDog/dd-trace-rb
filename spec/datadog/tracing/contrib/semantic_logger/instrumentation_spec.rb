require 'datadog/tracing/contrib/support/spec_helper'
require 'semantic_logger'
require 'datadog/tracing/contrib/semantic_logger/instrumentation'
require 'spec/support/thread_helpers'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Contrib::SemanticLogger::Instrumentation do
  let(:instrumented) { SemanticLogger::Logger.new('TestClass') }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :semantic_logger
    end
  end

  describe '#log' do
    subject(:log) do
      ThreadHelpers.with_leaky_thread_creation('semantic_logger log') do
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
    let(:trace_id) { Datadog::Tracing::Utils.next_id }
    let(:span_id) { Datadog::Tracing::Utils.next_id }
    let(:env) { 'env' }
    let(:service) { 'service' }
    let(:version) { 'version' }

    before do
      expect(Datadog::Tracing).to receive(:correlation).and_return(correlation)
    end

    it 'merges correlation data with original options' do
      assertion = proc do |event|
        expect(event.named_tags).to eq(
          { original: 'tag',
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

      if SemanticLogger::Logger.respond_to?(:call_subscribers)
        expect(SemanticLogger::Logger).to receive(:call_subscribers, &assertion) # semantic_logger >= 4.4.0
      else
        ThreadHelpers.with_leaky_thread_creation('semantic_logger processor') do
          expect(SemanticLogger::Processor).to receive(:<<, &assertion) # semantic_logger < 4.4.0
        end
      end

      log
    end
  end
end
