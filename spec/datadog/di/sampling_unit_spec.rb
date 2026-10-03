require "datadog/di/spec_helper"
require "datadog/di/sampling_unit"

RSpec.describe Datadog::DI::SamplingUnit do
  di_test

  def stub_active_trace(trace_id)
    trace = instance_double(Datadog::Tracing::TraceOperation, id: trace_id)
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
  end

  def stub_no_trace
    allow(Datadog::Tracing).to receive(:active_trace).and_return(nil)
  end

  describe ".current" do
    context "with an active APM trace" do
      before { stub_active_trace(123) }

      it "keys on the trace id" do
        expect(described_class.current.key).to eq(123)
      end
    end

    context "with no active trace" do
      before { stub_no_trace }

      it "has a nil key" do
        expect(described_class.current.key).to be_nil
      end
    end

    context "with an active trace that has no id" do
      before do
        trace = instance_double(Datadog::Tracing::TraceOperation, id: nil)
        allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
      end

      it "resolves to the NONE sentinel" do
        expect(described_class.current).to equal(described_class::NONE)
      end
    end

    context "when Datadog::Tracing is not defined" do
      before do
        hide_const("Datadog::Tracing")
      end

      it "resolves to the NONE sentinel" do
        expect(described_class.current).to equal(described_class::NONE)
      end
    end
  end
end
