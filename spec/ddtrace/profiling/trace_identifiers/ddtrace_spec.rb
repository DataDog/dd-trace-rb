# typed: false
require 'ddtrace/profiling/trace_identifiers/ddtrace'

require 'ddtrace/tracer'
require 'ddtrace/context'
require 'ddtrace/span'

RSpec.describe Datadog::Profiling::TraceIdentifiers::Ddtrace do
  let(:thread) { instance_double(Thread) }
  let(:tracer) { instance_double(Datadog::Tracer) }

  subject(:datadog_trace_identifiers) { described_class.new(tracer: tracer) }

  describe '#trace_identifiers_for' do
    subject(:trace_identifiers_for) { datadog_trace_identifiers.trace_identifiers_for(thread) }

    context 'when there is an active datadog trace for the thread' do
      let(:span_id) { rand(1e12) }
      let(:span) { instance_double(Datadog::Span, span_id: span_id) }
      let(:root_span_id) { rand(1e12) }
      let(:root_span_type) { nil }
      let(:root_span) { instance_double(Datadog::Span, span_id: root_span_id, span_type: root_span_type) }

      let(:context) do
        instance_double(Datadog::Context, current_span_and_root_span: [span, root_span])
      end

      before do
        expect(tracer).to receive(:call_context).with(thread).and_return(context)
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

    context 'when no datadog trace is active for the thread' do
      context 'and an empty context is returned' do
        before do
          expect(tracer).to receive(:call_context).and_return(Datadog::Context.new)
        end

        it do
          expect(trace_identifiers_for).to be nil
        end
      end

      context 'and no context is returned' do
        before do
          expect(tracer).to receive(:call_context).and_return(nil)
        end

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

    context 'when tracer does not support #call_context' do
      let(:tracer) { double('empty tracer') } # rubocop:disable RSpec/VerifiedDoubles

      it do
        expect(trace_identifiers_for).to be nil
      end
    end
  end
end
