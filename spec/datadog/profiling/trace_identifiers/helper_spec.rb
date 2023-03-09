require 'datadog/profiling/trace_identifiers/helper'
require 'datadog/profiling/trace_identifiers/ddtrace'

RSpec.describe Datadog::Profiling::TraceIdentifiers::Helper do
  let(:thread) { instance_double(Thread) }
  let(:api1) { instance_double(Datadog::Profiling::TraceIdentifiers::Ddtrace, 'api1') }
  let(:api2) { instance_double(Datadog::Profiling::TraceIdentifiers::Ddtrace, 'api2') }
  let(:endpoint_collection_enabled) { true }

  subject(:trace_identifiers_helper) do
    described_class.new(
      tracer: nil,
      endpoint_collection_enabled: endpoint_collection_enabled,
      supported_apis: [api1, api2]
    )
  end

  describe '::DEFAULT_SUPPORTED_APIS' do
    it 'contains the trace identifier extraction class for ddtrace' do
      expect(described_class.const_get(:DEFAULT_SUPPORTED_APIS))
        .to eq([::Datadog::Profiling::TraceIdentifiers::Ddtrace])
    end
  end

  describe '#trace_identifiers_for' do
    subject(:trace_identifiers_for) { trace_identifiers_helper.trace_identifiers_for(thread) }

    context 'when the first api provider returns trace identifiers' do
      before do
        allow(api1).to receive(:trace_identifiers_for).and_return([:api1_root_span_id, :api1_span_id])
      end

      it 'returns the first api provider trace identifiers' do
        expect(trace_identifiers_for).to eq [:api1_root_span_id, :api1_span_id]
      end

      it 'does not attempt to read trace identifiers from the second api provider' do
        expect(api2).to_not receive(:trace_identifiers_for)

        trace_identifiers_for
      end
    end

    context 'when the first api provider does not return trace identifiers, but the second one does' do
      before do
        allow(api1).to receive(:trace_identifiers_for).and_return(nil)
        allow(api2).to receive(:trace_identifiers_for).and_return([:api2_root_span_id, :api2_span_id])
      end

      it 'returns the second api provider trace identifiers' do
        expect(trace_identifiers_for).to eq [:api2_root_span_id, :api2_span_id]
      end
    end

    context 'when no api providers return trace identifiers' do
      before do
        allow(api1).to receive(:trace_identifiers_for).and_return(nil)
        allow(api2).to receive(:trace_identifiers_for).and_return(nil)
      end

      it do
        expect(trace_identifiers_for).to be nil
      end
    end

    context 'when the api provider returns a trace resource container together with the trace identifiers' do
      before do
        allow(api1)
          .to receive(:trace_identifiers_for)
          .and_return([:api1_root_span_id, :api1_span_id, :api1_trace_resource_container])
      end

      it 'returns the trace resource container together with the trace identifiers' do
        expect(trace_identifiers_for).to eq [:api1_root_span_id, :api1_span_id, :api1_trace_resource_container]
      end

      context 'and endpoint_collection_enabled is set to false' do
        let(:endpoint_collection_enabled) { false }

        it 'returns the trace identifiers but removes the trace resource container' do
          expect(trace_identifiers_for).to eq [:api1_root_span_id, :api1_span_id]
        end
      end
    end
  end
end
