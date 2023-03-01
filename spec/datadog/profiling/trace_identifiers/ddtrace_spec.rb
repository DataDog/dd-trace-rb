require 'datadog/profiling/trace_identifiers/ddtrace'
require 'datadog/tracing/span_operation'
require 'datadog/tracing/trace_operation'
require 'datadog/tracing/tracer'

RSpec.describe Datadog::Profiling::TraceIdentifiers::Ddtrace do
  let(:thread) { instance_double(Thread) }
  let(:tracer) { instance_double(Datadog::Tracing::Tracer) }

  subject(:datadog_trace_identifiers) { described_class.new(tracer: tracer) }

  describe '#trace_identifiers_for' do
    subject(:trace_identifiers_for) { datadog_trace_identifiers.trace_identifiers_for(thread) }

    context 'when there is an active datadog trace for the thread' do
      let(:root_span_id) { rand(1e12) }
      let(:root_span_type) { nil }
      let(:root_span) do
        instance_double(
          Datadog::Tracing::SpanOperation,
          id: root_span_id,
          span_type: root_span_type
        )
      end
      let(:resource) { nil }

      let(:span_id) { rand(1e12) }
      let(:span) { instance_double(Datadog::Tracing::SpanOperation, id: span_id) }

      let(:trace) do
        instance_double(
          Datadog::Tracing::TraceOperation,
          active_span: span,
          root_span: root_span,
          resource: resource
        )
      end

      before do
        allow(tracer).to receive(:active_trace).and_return(trace)
      end

      context "when root span type is 'web'" do
        let(:root_span_type) { 'web' }
        let(:resource) { 'example trace resource' }

        before do
          allow(root_span).to receive(:resource).and_return(resource)
        end

        it 'returns the identifiers and the trace container' do
          expect(trace_identifiers_for).to eq [root_span_id, span_id, resource]
        end
      end

      context "when root span type is not 'web'" do
        let(:root_span_type) { 'not web' }

        it 'returns the identifiers and no trace resource' do
          expect(trace_identifiers_for).to eq [root_span_id, span_id, nil]
        end

        it 'does not retrieve the resource' do
          trace_identifiers_for

          expect(root_span).to_not receive(:resource)
        end
      end

      context 'when root span is not available' do
        let(:root_span) { nil }

        it do
          expect(trace_identifiers_for).to be nil
        end
      end

      context 'when span is not available' do
        let(:span) { nil }

        it do
          expect(trace_identifiers_for).to be nil
        end
      end
    end

    context 'when no tracer instance is available' do
      let(:tracer) { nil }

      it do
        expect(trace_identifiers_for).to be nil
      end
    end

    context 'when no datadog trace is active for the thread' do
      context 'and nil is returned' do
        before do
          expect(tracer).to receive(:active_trace).and_return(nil)
        end

        it do
          expect(trace_identifiers_for).to be nil
        end
      end
    end
  end
end
