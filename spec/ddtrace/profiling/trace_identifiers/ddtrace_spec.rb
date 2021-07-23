require 'ddtrace/profiling/trace_identifiers/ddtrace'

require 'ddtrace/correlation'
require 'ddtrace/tracer'

RSpec.describe Datadog::Profiling::TraceIdentifiers::Ddtrace do
  let(:thread) { instance_double(Thread) }
  let(:tracer) { instance_double(Datadog::Tracer) }

  subject(:datadog_trace_identifiers) { described_class.new(tracer: tracer) }

  describe '#trace_identifiers_for' do
    subject(:trace_identifiers_for) { datadog_trace_identifiers.trace_identifiers_for(thread) }

    context 'when there is an active datadog trace for the thread' do
      let(:trace_id) { rand(1e12) }
      let(:span_id) { rand(1e12) }

      before do
        expect(tracer)
          .to receive(:active_correlation)
          .with(thread)
          .and_return(Datadog::Correlation::Identifier.new(trace_id, span_id))
      end

      it 'returns the identifiers' do
        trace_identifiers_for

        expect(trace_identifiers_for).to eq [trace_id, span_id]
      end
    end

    context 'when there is no active datadog trace for the thread' do
      before do
        expect(tracer)
          .to receive(:active_correlation)
          .with(thread)
          .and_return(Datadog::Correlation::Identifier.new)
      end

      it do
        expect(trace_identifiers_for).to be nil
      end
    end

    context 'when no tracer instance is available' do
      let(:tracer) { nil }

      it do
        expect(trace_identifiers_for).to be nil
      end
    end

    context 'when tracer does not support #active_correlation' do
      let(:tracer) { double('Tracer') } # rubocop:disable RSpec/VerifiedDoubles

      it do
        expect(trace_identifiers_for).to be nil
      end
    end
  end
end
