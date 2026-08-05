require "spec_helper"

require "datadog/tracing/sampling/ext"
require "datadog/tracing/distributed/open_telemetry_tracestate_codec"

RSpec.describe Datadog::Tracing::Distributed::OpenTelemetryTracestateCodec do
  describe ".resolve_outbound" do
    let(:trace_id) { 0xfff972474538efff }
    let(:sampling_priority) { 2 }
    let(:decision_maker) { Datadog::Tracing::Sampling::Ext::Decision::TRACE_SAMPLING_RULE }
    let(:applied_rate) { 0.1 }
    let(:rate_limiter_rate) { 1.0 }
    let(:inbound_random_value) { nil }
    let(:inbound_threshold) { nil }
    let(:distributed_sampling_priority) { false }

    subject(:resolve) do
      described_class.resolve_outbound(
        trace_id: trace_id,
        sampling_priority: sampling_priority,
        decision_maker: decision_maker,
        applied_rate: applied_rate,
        rate_limiter_rate: rate_limiter_rate,
        inbound_random_value: inbound_random_value,
        inbound_threshold: inbound_threshold,
        distributed_sampling_priority: distributed_sampling_priority,
      )
    end

    context "when a threshold was decided upstream" do
      let(:inbound_threshold) { "8" }

      it "forwards the threshold without fabricating a random value when only a threshold arrives" do
        # An OTel SDK that sets `th` without `rv` relies on the W3C implicit random value;
        # downstream participants re-derive it themselves, so we leave `rv` absent.
        expect(resolve).to eq([nil, "8"])
      end

      context "and a random value is also present" do
        let(:inbound_random_value) { "abcabcabcabcab" }

        it "forwards the inbound hex strings unchanged, without re-deciding" do
          expect(resolve).to eq(["abcabcabcabcab", "8"])
        end

        context "and the rate limiter drops the trace" do
          let(:rate_limiter_rate) { 0.5 }
          let(:sampling_priority) { -1 }

          it "erases the threshold but preserves the random value" do
            expect(resolve).to eq(["abcabcabcabcab", nil])
          end
        end

        context "and a non-probability decision maker force-keeps" do
          let(:decision_maker) { Datadog::Tracing::Sampling::Ext::Decision::MANUAL }

          it "erases the threshold but preserves the random value" do
            expect(resolve).to eq(["abcabcabcabcab", nil])
          end
        end
      end
    end

    context "when the rate limiter drops a purely local decision with no inbound values" do
      let(:rate_limiter_rate) { 0.5 }
      let(:sampling_priority) { -1 }

      it "emits no random value and no threshold" do
        expect(resolve).to eq([nil, nil])
      end
    end

    context "when only an inbound random value is present" do
      # This can happen when a trace is rate-limited or manually kept by a decision maker.
      let(:inbound_random_value) { "abcabcabcabcab" }

      it "forwards the inbound random value unchanged, without re-generating one" do
        expect(resolve).to eq(["abcabcabcabcab", nil])
      end
    end

    context "when DD makes a probability decision" do
      it "generates rv from the trace id and th from the rate (keep)" do
        expect(resolve).to eq(["ef284ace7a91e1", "e6666666666668"])
      end

      context "with a trace ID that would be dropped" do
        let(:trace_id) { 2 }
        let(:rate_limiter_rate) { nil }
        let(:sampling_priority) { -1 }

        it "generates rv from the trace id and th from the rate (drop)" do
          # A probabilistic drop never sets the rate limiter rate (the limiter only runs
          # after a rule already kept the trace). trace id 2 has rv e12914a9a8771c < th, so it
          # is a natural drop that needs no reconciliation.
          expect(resolve).to eq(["e12914a9a8771c", "e6666666666668"])
        end
      end

      # Derives the threshold from the applied rate, with trailing zero nibbles trimmed.
      # Only the threshold component is asserted here; reconciliation can adjust the random
      # value but never the threshold. rate 0.1 matches the RFC worked example.
      {
        1.0 => "0",
        0.75 => "4",
        0.5 => "8",
        0.25 => "c",
        0.1 => "e6666666666668",
        0.0 => "ffffffffffffff", # "never sample" clamped to the max encodable threshold
      }.each do |rate, expected_th|
        context "with rate #{rate}" do
          let(:applied_rate) { rate }

          it "derives threshold #{expected_th} from rate #{rate}" do
            expect(resolve[1]).to eq(expected_th)
          end
        end
      end

      {
        -1.0 => "ffffffffffffff",
        2.0 => "0",
      }.each do |rate, expected_th|
        context "with rate #{rate}" do
          let(:applied_rate) { rate }

          it "clamps an out-of-range applied rate" do
            expect(resolve[1]).to eq(expected_th)
          end
        end
      end

      context "with a 128-bit trace id" do
        let(:trace_id) { 0xabcdef << 64 | 0xfff972474538efff }

        it "derives the random value only from the trace id's lower 64 bits" do
          expect(resolve[0]).to eq("ef284ace7a91e1")
        end
      end
    end

    context "when the 56-bit threshold disagrees with Datadog's 64-bit decision (DD-Keep vs OTel-Drop)" do
      # Compressing the 64-bit keep/drop into a 56-bit threshold can flip the re-derived
      # `rv >= th` comparison. resolve_outbound nudges the random value across the boundary
      # so a downstream OpenTelemetry participant reaches the same decision Datadog made.
      let(:trace_id) { 263811222310854400 }
      let(:applied_rate) { 0.1 }
      let(:sampling_priority) { 2 }

      # trace id ...263811222310854400, rate 0.1
      # raw rv e6666666666666 < th e6666666666668 (OTel would drop)
      it "raises the random value to the threshold" do
        expect(resolve).to eq(["e6666666666668", "e6666666666668"])
      end
    end

    context "when the 56-bit threshold disagrees with Datadog's 64-bit decision (DD-Drop vs OTel-Keep)" do
      let(:trace_id) { 5401449561355763072 }
      let(:applied_rate) { 0.05 }
      let(:rate_limiter_rate) { nil }
      let(:sampling_priority) { 0 }

      # trace id ...5401449561355763072, rate 0.05
      # raw rv f3333333333331 >= th f3333333333330 (OTel would keep)
      it "lowers the random value below the threshold" do
        expect(resolve).to eq(["f333333333332f", "f333333333333"])
      end
    end

    context "and nothing probabilistic was decided" do
      let(:decision_maker) { nil }
      let(:applied_rate) { nil }
      let(:rate_limiter_rate) { nil }

      it "erases the threshold but preserves the random value" do
        expect(resolve).to eq([nil, nil])
      end
    end

    context "when a sampling priority was already assigned from an upstream distributed context" do
      # DD does not make its own probability decision here — it follows the inbound
      # sampling decision (traceparent sampled bit / X-Datadog-* headers). Even with a
      # local rate available, it must not fabricate `(rv, th)` the origin never sent.
      let(:distributed_sampling_priority) { true }

      it "emits nothing" do
        expect(resolve).to eq([nil, nil])
      end
    end
  end

  describe ".extract_otel_fields" do
    let(:otel_fields) { "rv:f972474538efff;th:8" }
    subject(:extract_otel_fields) { described_class.extract_otel_fields(otel_fields) }

    let(:extracted_otel_fields_class) { described_class.const_get(:ExtractedOtelFields) }

    it "parses the random value and threshold as raw hex strings" do
      is_expected.to eq(extracted_otel_fields_class.new("f972474538efff", "8", nil))
    end

    context "with unknown sub-keys" do
      let(:otel_fields) { "th:8;future:x;more:y" }

      it "preserves unknown sub-keys with a trailing semicolon" do
        is_expected.to eq(extracted_otel_fields_class.new(nil, "8", "future:x;more:y;"))
      end
    end

    context "with a threshold only" do
      let(:otel_fields) { "th:e6666666666668" }

      it "parses a threshold with no random value (implicit random value case)" do
        is_expected.to eq(extracted_otel_fields_class.new(nil, "e6666666666668", nil))
      end
    end

    [
      "th:", # empty
      "th:xyz", # non-hex
      "th:E6666666666668", # uppercase
      "th:f00000000000000", # 15 digits, exceeds 56 bits
    ].each do |member|
      context "when the threshold is malformed with #{member}" do
        let(:otel_fields) { "rv:f972474538efff;#{member}" }

        it "ignores #{member} while keeping a valid random value" do
          is_expected.to eq(extracted_otel_fields_class.new("f972474538efff", nil, nil))
        end
      end
    end

    [
      "rv:", # empty
      "rv:xyz", # non-hex
      "rv:f972474538eff", # 13 digits, too short
      "rv:f972474538efff0", # 15 digits, too long
    ].each do |member|
      context "when the random value is malformed with #{member}" do
        let(:otel_fields) { "#{member};th:8" }

        it "ignores #{member} but keeps a valid threshold" do
          is_expected.to eq(extracted_otel_fields_class.new(nil, "8", nil))
        end
      end
    end
  end
end
