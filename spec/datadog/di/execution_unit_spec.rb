require "datadog/di/spec_helper"
require "datadog/di/execution_unit"

RSpec.describe Datadog::DI::ExecutionUnit do
  di_test

  def stub_active_trace(trace_id, span_id: nil)
    trace = double("trace", id: trace_id)
    span = span_id && double("span", id: span_id)
    allow(Datadog::Tracing).to receive(:active_trace).and_return(trace)
    allow(Datadog::Tracing).to receive(:active_span).and_return(span)
  end

  def stub_no_trace
    allow(Datadog::Tracing).to receive(:active_trace).and_return(nil)
    allow(Datadog::Tracing).to receive(:active_span).and_return(nil)
  end

  describe ".current" do
    context "with an active APM trace" do
      before { stub_active_trace("trace-1", span_id: "span-1") }

      it "keys on the trace id, scopes on the span id, sources apm" do
        u = described_class.current
        expect(u.key).to eq("trace-1")
        expect(u.scope).to eq("span-1")
        expect(u.source).to eq(:apm)
      end

      it "falls back to the trace id for the scope when no span is active" do
        stub_active_trace("trace-1")
        expect(described_class.current.scope).to eq("trace-1")
      end
    end

    context "with no active trace" do
      before { stub_no_trace }

      it "has a nil key and scope, sources none" do
        u = described_class.current
        expect(u.key).to be_nil
        expect(u.scope).to be_nil
        expect(u.source).to eq(:none)
      end
    end
  end
end
