require "spec_helper"

require "datadog/tracing/distributed/trace_state"
require "datadog/tracing/trace_digest"

RSpec.describe Datadog::Tracing::Distributed::TraceState do
  describe ".build" do
    let(:digest) do
      Datadog::Tracing::TraceDigest.new(
        trace_sampling_priority: 1,
        trace_state: "vendor=value",
        trace_otel_sampling_fields: sampling_fields.new("ef284ace7a91e1", "8")
      )
    end
    let(:sampling_fields) do
      Datadog::Tracing::Distributed::OpenTelemetryTracestateCodec::OpenTelemetrySamplingFields
    end

    it "assembles Datadog, OpenTelemetry, and pass-through vendors" do
      expect(described_class.build(digest)).to eq("dd=s:1,ot=rv:ef284ace7a91e1;th:8,vendor=value")
    end
  end

  describe ".extract" do
    subject(:extracted) { described_class.extract("dd=s:1,ot=rv:ef284ace7a91e1;th:8,vendor=value") }

    it "extracts owned vendors and preserves pass-through vendors" do
      expect(extracted.tracestate).to eq("vendor=value")
      expect(extracted.dd.sampling_priority).to eq(1)
      expect(extracted.ot.sampling_fields).to eq(
        Datadog::Tracing::Distributed::OpenTelemetryTracestateCodec::OpenTelemetrySamplingFields.new(
          "ef284ace7a91e1",
          "8"
        )
      )
    end
  end

  describe "vendor building" do
    it "removes the trailing field separator before selecting vendors" do
      digest = Datadog::Tracing::TraceDigest.new(trace_sampling_priority: 1)

      expect(described_class.send(:build_dd_vendor, digest)).to eq("dd=s:1")
    end
  end

  describe ".split" do
    it "uses an extra result to detect and discard a 33rd vendor" do
      value = Array.new(33) { |index| "v#{index}=1" }.join(",")

      expect(described_class.send(:split, value)).to eq(Array.new(32) { |index| "v#{index}=1" })
    end

    it "discards trailing blank members after stripping whitespace" do
      expect(described_class.send(:split, "v=1,   ,")).to eq(["v=1"])
    end
  end
end
