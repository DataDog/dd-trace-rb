require "spec_helper"

require "datadog/tracing/distributed/trace_state"
require "datadog/tracing/trace_digest"

RSpec.describe Datadog::Tracing::Distributed::TraceState do
  describe ".serialize_digest" do
    let(:digest) do
      Datadog::Tracing::TraceDigest.new(
        trace_sampling_priority: 1,
        trace_state: "vendor=value",
        trace_otel_random_value: "ef284ace7a91e1",
        trace_otel_threshold: "8"
      )
    end

    it "assembles Datadog, OpenTelemetry, and pass-through vendors" do
      expect(described_class.serialize_digest(digest)).to eq(
        "dd=s:1,ot=rv:ef284ace7a91e1;th:8,vendor=value"
      )
    end
  end

  describe ".extract" do
    subject(:extracted) { described_class.extract("dd=s:1,ot=rv:ef284ace7a91e1;th:8,vendor=value") }

    it "extracts owned vendors and preserves pass-through vendors" do
      expect(extracted.unknown_vendors).to eq("vendor=value")
      expect(extracted.datadog.sampling_priority).to eq(1)
      expect(extracted.open_telemetry).to have_attributes(
        random_value: "ef284ace7a91e1",
        threshold: "8"
      )
    end
  end

  describe ".from_digest" do
    subject(:trace_state) { described_class.from_digest(digest, propagate_sampling: propagate_sampling) }

    let(:digest) do
      Datadog::Tracing::TraceDigest.new(
        span_id: 15,
        span_remote: false,
        trace_origin: "synthetics",
        trace_sampling_priority: 1,
        trace_distributed_tags: {"_dd.p.test" => "value"},
        trace_state_unknown_fields: "future:value;",
        trace_otel_random_value: "ef284ace7a91e1",
        trace_otel_threshold: "8",
        trace_otel_unknown_fields: "future:value;"
      )
    end
    let(:propagate_sampling) { true }

    it "converts all parsed digest values" do
      expect(trace_state.unknown_vendors).to eq(digest.trace_state)
      expect(trace_state.datadog).to have_attributes(
        sampling_priority: 1,
        origin: "synthetics",
        ts_parent_id: "000000000000000f",
        tags: {"_dd.p.test" => "value"},
        unknown_fields: "future:value;"
      )
      expect(trace_state.open_telemetry).to have_attributes(
        random_value: "ef284ace7a91e1",
        threshold: "8",
        unknown_fields: "future:value;"
      )
    end

    context "without sampling propagation" do
      let(:propagate_sampling) { false }

      it "keeps only pass-through OpenTelemetry fields" do
        expect(trace_state.open_telemetry).to have_attributes(
          random_value: nil,
          threshold: nil,
          unknown_fields: "future:value;"
        )
      end
    end
  end

  describe ".split" do
    it "uses an extra result to detect and discard a 33rd vendor" do
      value = Array.new(33) { |index| "v#{index}=1" }.join(",")

      expect(described_class.split(value)).to eq(Array.new(32) { |index| "v#{index}=1" })
    end

    it "discards trailing blank members after stripping whitespace" do
      expect(described_class.split("v=1,   ,")).to eq(["v=1"])
    end
  end
end
