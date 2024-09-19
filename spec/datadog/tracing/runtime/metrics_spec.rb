require 'spec_helper'

require 'datadog/core'
require 'datadog/tracing/runtime/metrics'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_segment'

RSpec.describe Datadog::Tracing::Runtime::Metrics do
  describe '::associate_trace' do
    subject(:associate_trace) { described_class.associate_trace(trace) }

    context 'when given nil' do
      let(:trace) { nil }

      it 'does nothing' do
        expect(Datadog.send(:components).runtime_metrics).to_not receive(:register_service)
        associate_trace
      end
    end

    context 'when given a trace' do
      let(:trace) { Datadog::Tracing::TraceSegment.new(spans, service: service) }

      context 'with a service but no spans' do
        let(:spans) { [] }
        let(:service) { nil }

        it 'does not register the trace\'s service' do
          expect(Datadog.send(:components).runtime_metrics).to_not receive(:register_service)
          associate_trace
        end
      end

      context 'without a service but with spans' do
        let(:spans) { Array.new(2) { Datadog::Tracing::Span.new('my.task', service: 'parser') } }
        let(:service) { nil }

        it 'does not register the trace\'s service' do
          expect(Datadog.send(:components).runtime_metrics).to_not receive(:register_service)
          associate_trace
        end
      end

      context 'with a service and spans' do
        let(:spans) { Array.new(2) { Datadog::Tracing::Span.new('my.task', service: service) } }
        let(:service) { 'parser' }

        it 'registers the trace\'s service' do
          expect(Datadog.send(:components).runtime_metrics).to receive(:register_service).with(service)
          associate_trace
        end
      end
    end
  end
end
