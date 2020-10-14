require 'spec_helper'
require 'ddtrace/context'
require 'ddtrace/propagation/grpc_propagator'

RSpec.describe Datadog::GRPCPropagator do
  describe '.inject!' do
    subject { described_class }

    let(:span_context) do
      Datadog::Context.new(trace_id: 1234567890,
                           span_id: 9876543210,
                           sampling_priority: sampling_priority,
                           origin: origin)
    end

    let(:sampling_priority) { nil }
    let(:origin) { nil }

    let(:metadata) { {} }

    before { subject.inject!(span_context, metadata) }

    it 'injects the context trace id into the gRPC metadata' do
      expect(metadata).to include('x-datadog-trace-id' => '1234567890')
    end

    it 'injects the context parent span id into the gRPC metadata' do
      expect(metadata).to include('x-datadog-parent-id' => '9876543210')
    end

    context 'when sampling priority set on context' do
      let(:sampling_priority) { 0 }

      it 'injects the sampling priority into the gRPC metadata' do
        expect(metadata).to include('x-datadog-sampling-priority' => '0')
      end
    end

    context 'when sampling priority not set on context' do
      it 'leaves the sampling priority blank in the gRPC metadata' do
        expect(metadata).not_to include('x-datadog-sampling-priority')
      end
    end

    context 'when origin set on context' do
      let(:origin) { 'synthetics' }

      it 'injects the origin into the gRPC metadata' do
        expect(metadata).to include('x-datadog-origin' => 'synthetics')
      end
    end

    context 'when origin not set on context' do
      it 'leaves the origin blank in the gRPC metadata' do
        expect(metadata).not_to include('x-datadog-origin')
      end
    end
  end

  describe '.extract' do
    subject { described_class.extract(metadata) }

    context 'given empty metadata' do
      let(:metadata) { {} }

      it 'returns an empty context' do
        expect(subject.trace_id).to be_nil
        expect(subject.span_id).to be_nil
        expect(subject.sampling_priority).to be_nil
      end
    end

    context 'given populated metadata' do
      let(:metadata) do
        { 'x-datadog-trace-id' => '1234567890',
          'x-datadog-parent-id' => '9876543210',
          'x-datadog-sampling-priority' => '0',
          'x-datadog-origin' => 'synthetics' }
      end

      it 'returns a populated context' do
        expect(subject.trace_id).to eq 1234567890
        expect(subject.span_id).to eq 9876543210
        expect(subject.sampling_priority).to be_zero
        expect(subject.origin).to eq 'synthetics'
      end
    end

    # Metadata values can also be arrays
    # https://github.com/grpc/grpc-go/blob/master/Documentation/grpc-metadata.md
    context 'given populated metadata in array format' do
      let(:metadata) do
        { 'x-datadog-trace-id' => %w[12345 67890],
          'x-datadog-parent-id' => %w[98765 43210],
          'x-datadog-sampling-priority' => ['0'],
          'x-datadog-origin' => ['synthetics'] }
      end

      it 'returns a populated context with the first metadata array values' do
        expect(subject.trace_id).to eq 12345
        expect(subject.span_id).to eq 98765
        expect(subject.sampling_priority).to be_zero
        expect(subject.origin).to eq 'synthetics'
      end
    end
  end
end
