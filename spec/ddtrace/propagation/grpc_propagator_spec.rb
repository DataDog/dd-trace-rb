require 'spec_helper'
require 'ddtrace/tracer'
require 'ddtrace/propagation/grpc_propagator'

RSpec.describe 'gRPC propagation of distributed span context' do
  subject { Datadog::GRPCPropagator }

  let(:span_context) { Datadog::Tracer.new.trace('test').context }
  let(:metadata) { { 'something' => 'special' } }

  describe '.inject!' do
    context 'injecting context without sampling priority' do
      specify do
        subject.inject!(span_context, metadata)

        expect(metadata).to include 'something' => 'special'
        expect(metadata).to include Datadog::Ext::DistributedTracing::GRPC_METADATA_TRACE_ID => span_context.trace_id.to_s
        expect(metadata).to include Datadog::Ext::DistributedTracing::GRPC_METADATA_PARENT_ID => span_context.span_id.to_s
        expect(metadata).not_to include Datadog::Ext::DistributedTracing::GRPC_METADATA_SAMPLING_PRIORITY
      end
    end

    context 'injecting context with sampling priority' do
      specify do
        span_context.sampling_priority = 0
        subject.inject!(span_context, metadata)

        expect(metadata).to include 'something' => 'special'
        expect(metadata).to include Datadog::Ext::DistributedTracing::GRPC_METADATA_TRACE_ID => span_context.trace_id.to_s
        expect(metadata).to include Datadog::Ext::DistributedTracing::GRPC_METADATA_PARENT_ID => span_context.span_id.to_s
        expect(metadata).to include Datadog::Ext::DistributedTracing::GRPC_METADATA_SAMPLING_PRIORITY => '0'
      end
    end

    context 'injecting context with nil sampling priority' do
      specify do
        span_context.sampling_priority = nil
        subject.inject!(span_context, metadata)

        expect(metadata).to include 'something' => 'special'
        expect(metadata).to include Datadog::Ext::DistributedTracing::GRPC_METADATA_TRACE_ID => span_context.trace_id.to_s
        expect(metadata).to include Datadog::Ext::DistributedTracing::GRPC_METADATA_PARENT_ID => span_context.span_id.to_s
        expect(metadata).not_to include Datadog::Ext::DistributedTracing::GRPC_METADATA_SAMPLING_PRIORITY
      end
    end
  end

  describe 'extract' do
    context 'from empty metadata' do
      specify do
        span_context = subject.extract({})

        expect(span_context.trace_id).to be_nil
        expect(span_context.span_id).to be_nil
        expect(span_context.sampling_priority).to be_nil
      end
    end

    context 'from nil metadata' do
      specify do
        span_context = subject.extract(nil)

        expect(span_context.trace_id).to be_nil
        expect(span_context.span_id).to be_nil
        expect(span_context.sampling_priority).to be_nil
      end
    end

    context 'from distributed tracing metadata lacking sampling priority' do
      specify do
        span_context = subject.extract({
          'x-datadog-trace-id' => '42',
          'x-datadog-parent-id' => '24'
        })

        expect(span_context.trace_id).to eq 42
        expect(span_context.span_id).to eq 24
        expect(span_context.sampling_priority).to be_nil
      end
    end

    context 'from distributed tracing metadata including sampling priority' do
      specify do
        span_context = subject.extract({
          'x-datadog-trace-id' => '42',
          'x-datadog-parent-id' => '24',
          'x-datadog-sampling-priority' => '0'
        })

        expect(span_context.trace_id).to eq 42
        expect(span_context.span_id).to eq 24
        expect(span_context.sampling_priority).to eq 0
      end
    end
  end
end
