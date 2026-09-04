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
  end
end
