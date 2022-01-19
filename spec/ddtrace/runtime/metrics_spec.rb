# typed: false
require 'spec_helper'
require 'ddtrace'
require 'ddtrace/runtime/metrics'

RSpec.describe Datadog::Runtime::Metrics do
  let(:options) { {} }

  describe '::associate_trace' do
    subject(:associate_trace) { described_class.associate_trace(trace) }

    let(:trace) { Datadog::TraceSegment.new('dummy', service: service) }
    let(:service) { 'parser' }

    context 'when enabled' do
      before do
        Datadog.configure { |c| c.runtime_metrics.enabled = true }
        associate_trace
      end

      after { Datadog.configure { |c| c.runtime_metrics.enabled = false } }

      context 'and given' do
        it 'registers the trace\'s service' do
          expect(Datadog.runtime_metrics.metrics.default_metric_options[:tags]).to include("service:#{service}")
        end
      end
    end

    context 'when disabled' do
      before do
        Datadog.configure { |c| c.runtime_metrics.enabled = false }
        associate_trace
      end

      it 'does not register the trace\'s service' do
        expect(Datadog.runtime_metrics.metrics.default_metric_options[:tags]).to_not include("service:#{service}")
      end
    end
  end
end
