require 'datadog/tracing/contrib/support/spec_helper'
require 'semantic_logger'
require 'datadog/tracing/contrib/semantic_logger/instrumentation'
require 'spec/support/thread_helpers'
require 'datadog/tracing/utils'

RSpec.describe Datadog::Tracing::Contrib::SemanticLogger::Instrumentation do
  let(:logger) { SemanticLogger::Logger.new('TestClass') }
  let(:log_output) do
    StringIO.new
  end
  let(:log_injection) { true }
  let(:semantic_logger_enabled) { true }

  before do
    Datadog.configure do |c|
      c.tracing.log_injection = log_injection
      c.tracing.instrument :semantic_logger, enabled: semantic_logger_enabled
    end
  end

  after do
    Datadog.configuration.tracing.reset!
    Datadog.configuration.tracing[:semantic_logger].reset_options!
  end

  around do |example|
    SemanticLogger.add_appender(io: log_output)
    example.run
    SemanticLogger.close
  end

  describe '#log' do
    subject(:log) do
      ThreadHelpers.with_leaky_thread_creation('semantic_logger log') do
        logger.log(event).tap do
          SemanticLogger.flush
        end
      end
    end

    let(:event) do
      SemanticLogger::Log.new('Mamamia!', :info).tap do |e|
        e.named_tags = { original: 'tag' }
      end
    end

    let(:trace_id) { Datadog::Tracing::Utils::TraceId.next_id }
    let(:span_id) { Datadog::Tracing::Utils.next_id }

    let(:correlation) do
      Datadog::Tracing::Correlation::Identifier.new(
        trace_id: trace_id,
        span_id: span_id,
        env: 'production',
        service: 'MyService',
        version: '1.2.3',
      )
    end

    before do
      allow(Datadog::Tracing).to receive(:correlation).and_return(correlation)
    end

    context 'when log_injection and semantic_logger enabled' do
      it 'merges correlation data with original options' do
        log

        log_entry = log_output.string

        expect(log_entry).to include 'Mamamia!'
        expect(log_entry).to include 'original: tag'

        expect(log_entry).to include low_order_trace_id(trace_id).to_s
        expect(log_entry).to include span_id.to_s
        expect(log_entry).to include 'production'
        expect(log_entry).to include 'MyService'
        expect(log_entry).to include '1.2.3'
        expect(log_entry).to include 'ddsource: ruby'
      end
    end

    context 'when log_injection disabled' do
      let(:log_injection) { false }

      it 'does not merges correlation data with original options' do
        log

        log_entry = log_output.string

        expect(log_entry).to include 'Mamamia!'
        expect(log_entry).to include 'original: tag'

        expect(log_entry).not_to include low_order_trace_id(trace_id).to_s
        expect(log_entry).not_to include span_id.to_s
        expect(log_entry).not_to include 'production'
        expect(log_entry).not_to include 'MyService'
        expect(log_entry).not_to include '1.2.3'
        expect(log_entry).not_to include 'ddsource: ruby'
      end
    end

    context 'when ssemantic_logger disabled' do
      let(:semantic_logger_enabled) { false }

      it 'does not merges correlation data with original options' do
        log

        log_entry = log_output.string

        expect(log_entry).to include 'Mamamia!'
        expect(log_entry).to include 'original: tag'

        expect(log_entry).not_to include low_order_trace_id(trace_id).to_s
        expect(log_entry).not_to include span_id.to_s
        expect(log_entry).not_to include 'production'
        expect(log_entry).not_to include 'MyService'
        expect(log_entry).not_to include '1.2.3'
        expect(log_entry).not_to include 'ddsource: ruby'
      end
    end

    context 'when log in Logger compatible mode' do
      subject(:log) do
        ThreadHelpers.with_leaky_thread_creation('semantic_logger log_compatible') do
          logger.log(::Logger::INFO, 'Mamamia!').tap do
            SemanticLogger.flush
          end
        end
      end

      it 'merges correlation data' do
        log

        log_entry = log_output.string

        expect(log_entry).to include 'Mamamia!'
        expect(log_entry).not_to include 'original: tag'

        expect(log_entry).to include low_order_trace_id(trace_id).to_s
        expect(log_entry).to include span_id.to_s
        expect(log_entry).to include 'production'
        expect(log_entry).to include 'MyService'
        expect(log_entry).to include '1.2.3'
        expect(log_entry).to include 'ddsource: ruby'
      end
    end
  end
end
