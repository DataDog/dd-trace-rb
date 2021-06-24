require 'ddtrace/profiling/trace_identifiers/opentelemetry'

RSpec.describe Datadog::Profiling::TraceIdentifiers::OpenTelemetry do
  before(:all) do
    skip 'opentelemetry-api not supported on Ruby < 2.5' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.5.0')

    require 'opentelemetry-api'
  end

  let(:thread) { Thread.new { sleep } }

  subject(:opentelemetry_trace_identifiers) { described_class.new }

  after do
    thread.kill
    thread.join
  end

  describe '#trace_identifiers_for' do
    subject(:trace_identifiers_for) { opentelemetry_trace_identifiers.trace_identifiers_for(thread) }

    context 'when there is an active opentelemetry trace for the thread' do
      let!(:thread) do
        Thread.new(span_queue) do |span_queue|
          OpenTelemetry.tracer_provider.tracer('ddtrace_testing', '1.2.3').in_span('test_span') do |span|
            span_queue << span
            sleep
          end
        end
      end
      let(:span_queue) { Queue.new }

      it 'returns the identifiers as a pair of 64 bit integers' do
        span_context = span_queue.pop.context

        expect(trace_identifiers_for)
          .to eq [span_context.hex_trace_id[16..-1].to_i(16), span_context.hex_span_id.to_i(16)]
      end
    end

    context 'when there there is no opentelemetry span (nil) for the thread' do
      before do
        allow(OpenTelemetry::Trace).to receive(:current_span).and_return(nil)
      end

      it do
        expect(trace_identifiers_for).to be nil
      end
    end

    context 'when there there is no opentelemetry span (invalid) for the thread' do
      before do
        allow(OpenTelemetry::Trace).to receive(:current_span).and_return(OpenTelemetry::Trace::Span::INVALID)
      end

      it do
        expect(trace_identifiers_for).to be nil
      end
    end

    context 'when an unsupported version of the opentelemetry-api gem is loaded' do
      before do
        allow(Datadog.logger).to receive(:warn)
        stub_const('::OpenTelemetry::VERSION', '0.16.0')
        described_class.const_get('UNSUPPORTED_VERSION_ONLY_ONCE').send(:reset_ran_once_state_for_tests)
      end

      it 'does not try to invoke the opentelemetry api' do
        expect(OpenTelemetry::Trace).to_not receive(:current_span)

        trace_identifiers_for
      end

      it 'logs a warning' do
        expect(Datadog.logger).to receive(:warn).with(/Incompatible version of opentelemetry-api/)

        trace_identifiers_for
      end
    end

    context 'when opentelemetry-api gem is not available' do
      let!(:original_opentelemetry) { ::OpenTelemetry }

      before do
        hide_const('::OpenTelemetry')
      end

      it do
        expect(trace_identifiers_for).to be nil
      end

      context 'but becomes available after the first call' do
        let!(:thread) do
          Thread.new(span_queue, start_trace_queue) do |span_queue, start_trace_queue|
            start_trace_queue.pop # Wait until we're asked to start the trace

            OpenTelemetry.tracer_provider.tracer('ddtrace_testing', '1.2.3').in_span('test_span') do |span|
              span_queue << span
              sleep
            end
          end
        end
        let(:span_queue) { Queue.new }
        let(:start_trace_queue) { Queue.new }

        it 'returns the trace identifiers' do
          # first call has no identifiers
          expect(trace_identifiers_for).to be nil

          # simulate OpenTelemetry becoming available
          stub_const('::OpenTelemetry', original_opentelemetry)

          # allow and wait for trace to start
          start_trace_queue << true
          span_queue.pop.context

          expect(opentelemetry_trace_identifiers.trace_identifiers_for(thread)).to_not be nil
        end
      end
    end
  end
end
