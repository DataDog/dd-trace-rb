# typed: false
require 'spec_helper'

require 'datadog/tracing/propagation/grpc'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Propagation::GRPC do
  describe '::inject!' do
    subject!(:inject!) { described_class.inject!(trace, metadata) }
    let(:metadata) { {} }

    shared_examples_for 'trace injection' do
      let(:trace_id) { 1234567890 }
      let(:span_id) { 9876543210 }
      let(:sampling_priority) { nil }
      let(:origin) { nil }

      it 'injects the trace id into the gRPC metadata' do
        expect(metadata).to include('x-datadog-trace-id' => '1234567890')
      end

      it 'injects the parent span id into the gRPC metadata' do
        expect(metadata).to include('x-datadog-parent-id' => '9876543210')
      end

      context 'when sampling priority is set' do
        let(:sampling_priority) { 0 }

        it 'injects the sampling priority into the gRPC metadata' do
          expect(metadata).to include('x-datadog-sampling-priority' => '0')
        end
      end

      context 'when sampling priority is not set' do
        it 'leaves the sampling priority blank in the gRPC metadata' do
          expect(metadata).not_to include('x-datadog-sampling-priority')
        end
      end

      context 'when origin is set' do
        let(:origin) { 'synthetics' }

        it 'injects the origin into the gRPC metadata' do
          expect(metadata).to include('x-datadog-origin' => 'synthetics')
        end
      end

      context 'when origin is not set' do
        it 'leaves the origin blank in the gRPC metadata' do
          expect(metadata).not_to include('x-datadog-origin')
        end
      end
    end

    context 'given nil' do
      let(:trace) { nil }
      it { expect(metadata).to eq({}) }
    end

    context 'given a TraceDigest and env' do
      let(:trace) do
        Datadog::Tracing::TraceDigest.new(
          span_id: span_id,
          trace_id: trace_id,
          trace_origin: origin,
          trace_sampling_priority: sampling_priority
        )
      end

      it_behaves_like 'trace injection'
    end

    context 'given a TraceOperation and env' do
      let(:trace) do
        Datadog::Tracing::TraceOperation.new(
          id: trace_id,
          origin: origin,
          parent_span_id: span_id,
          sampling_priority: sampling_priority
        )
      end

      it_behaves_like 'trace injection'
    end
  end

  describe '.extract' do
    subject(:extract) { described_class.extract(metadata) }
    let(:trace_digest) { extract }

    context 'given empty metadata' do
      let(:metadata) { nil }
      it { is_expected.to be nil }
    end

    context 'given populated metadata' do
      let(:metadata) do
        { 'x-datadog-trace-id' => '1234567890',
          'x-datadog-parent-id' => '9876543210',
          'x-datadog-sampling-priority' => '0',
          'x-datadog-origin' => 'synthetics' }
      end

      it 'returns a populated TraceDigest' do
        expect(trace_digest.span_id).to eq 9876543210
        expect(trace_digest.trace_id).to eq 1234567890
        expect(trace_digest.trace_origin).to eq 'synthetics'
        expect(trace_digest.trace_sampling_priority).to be_zero
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

      it 'returns a populated TraceDigest with the first metadata array values' do
        expect(trace_digest.span_id).to eq 98765
        expect(trace_digest.trace_id).to eq 12345
        expect(trace_digest.trace_origin).to eq 'synthetics'
        expect(trace_digest.trace_sampling_priority).to be_zero
      end
    end
  end
end
