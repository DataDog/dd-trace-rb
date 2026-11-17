require "datadog/di/spec_helper"
require "datadog/di/snapshot_correlation"
require "datadog/tracing/trace_operation"
require "datadog/tracing/span_operation"

RSpec.describe Datadog::DI::SnapshotCorrelation do
  describe ".capture" do
    subject(:correlation) { described_class.capture(trace) }

    context "with an active trace" do
      let(:span) { instance_double(Datadog::Tracing::SpanOperation) }
      let(:trace) { instance_double(Datadog::Tracing::TraceOperation, active_span: span) }

      it "pairs the trace with the span active in it" do
        expect(correlation.trace).to equal(trace)
        expect(correlation.span).to equal(span)
      end
    end

    context "with an active trace that has no active span" do
      let(:trace) { instance_double(Datadog::Tracing::TraceOperation, active_span: nil) }

      it "pairs the trace with no span" do
        expect(correlation.trace).to equal(trace)
        expect(correlation.span).to be_nil
      end
    end

    context "without an active trace" do
      let(:trace) { nil }

      it "holds no trace and no span" do
        expect(correlation.trace).to be_nil
        expect(correlation.span).to be_nil
      end
    end
  end
end
