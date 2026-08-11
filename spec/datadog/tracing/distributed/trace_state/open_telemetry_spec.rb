require "spec_helper"

require "datadog/tracing/sampling/ext"
require "datadog/tracing/distributed/trace_state/open_telemetry"
require "datadog/tracing/trace_digest"

RSpec.describe Datadog::Tracing::Distributed::TraceState::OpenTelemetry do
  describe ".from_digest" do
    subject(:from_digest) { described_class.from_digest(digest, propagate_sampling: propagate_sampling) }

    let(:digest) do
      Datadog::Tracing::TraceDigest.new(
        trace_otel_random_value: "ef284ace7a91e1",
        trace_otel_threshold: "8",
        trace_otel_unknown_fields: "future:value;"
      )
    end
    let(:propagate_sampling) { true }

    it "copies parsed OpenTelemetry fields" do
      is_expected.to have_attributes(
        random_value: "ef284ace7a91e1",
        threshold: "8",
        unknown_fields: "future:value;"
      )
    end

    context "without sampling propagation" do
      let(:propagate_sampling) { false }

      it "copies only pass-through fields" do
        is_expected.to have_attributes(
          random_value: nil,
          threshold: nil,
          unknown_fields: "future:value;"
        )
      end
    end
  end

  describe "#outbound" do
    subject(:resolved) do
      inbound.outbound(
        trace_id: trace_id,
        sampling_priority: sampling_priority,
        decision_maker: decision_maker,
        applied_rate: applied_rate,
        rate_limiter_rate: rate_limiter_rate,
        distributed_sampling_priority: distributed_sampling_priority,
      )
    end

    let(:trace_id) { 0xfff972474538efff }
    let(:sampling_priority) { 2 }
    let(:decision_maker) { Datadog::Tracing::Sampling::Ext::Decision::TRACE_SAMPLING_RULE }
    let(:applied_rate) { 0.1 }
    let(:rate_limiter_rate) { 1.0 }
    let(:inbound) { described_class.new }
    let(:distributed_sampling_priority) { false }

    context "with an upstream threshold and random value" do
      let(:inbound) { described_class.new(random_value: "abcabcabcabcab", threshold: "8") }

      it "forwards both values" do
        is_expected.to have_attributes(random_value: "abcabcabcabcab", threshold: "8")
      end

      context "when the rate limiter drops the trace" do
        let(:rate_limiter_rate) { 0.5 }
        let(:sampling_priority) { -1 }

        it "removes the threshold" do
          is_expected.to have_attributes(random_value: "abcabcabcabcab", threshold: nil)
        end
      end

      context "with a non-probability decision" do
        let(:decision_maker) { Datadog::Tracing::Sampling::Ext::Decision::MANUAL }

        it "removes the threshold" do
          is_expected.to have_attributes(random_value: "abcabcabcabcab", threshold: nil)
        end
      end
    end

    context "with only an upstream threshold" do
      let(:inbound) { described_class.new(threshold: "8") }

      it "does not fabricate a random value" do
        is_expected.to have_attributes(random_value: nil, threshold: "8")
      end
    end

    context "with only an upstream random value" do
      let(:inbound) { described_class.new(random_value: "abcabcabcabcab") }

      it "forwards it" do
        is_expected.to have_attributes(random_value: "abcabcabcabcab", threshold: nil)
      end
    end

    context "when a local decision is rate-limited" do
      let(:rate_limiter_rate) { 0.5 }
      let(:sampling_priority) { -1 }

      it "does not emit sampling fields" do
        expect(resolved.build).to be_empty
      end
    end

    context "when a local decision is not probabilistic" do
      let(:decision_maker) { Datadog::Tracing::Sampling::Ext::Decision::MANUAL }

      it "does not emit sampling fields" do
        expect(resolved.build).to be_empty
      end
    end

    context "when Datadog makes a probability decision" do
      it "derives the random value and threshold" do
        is_expected.to have_attributes(random_value: "ef284ace7a91e1", threshold: "e6666666666668")
      end

      {
        1.0 => "0",
        0.75 => "4",
        0.5 => "8",
        0.25 => "c",
        0.1 => "e6666666666668",
        0.0 => "ffffffffffffff",
        -1.0 => "ffffffffffffff",
        2.0 => "0",
      }.each do |rate, expected_threshold|
        context "with rate #{rate}" do
          let(:applied_rate) { rate }

          it "derives threshold #{expected_threshold}" do
            expect(resolved.threshold).to eq(expected_threshold)
          end
        end
      end

      context "with a 128-bit trace id" do
        let(:trace_id) { 0xabcdef << 64 | 0xfff972474538efff }

        it "uses the lower 64 bits" do
          expect(resolved.random_value).to eq("ef284ace7a91e1")
        end
      end

      context "when the trace is dropped" do
        let(:trace_id) { 2 }
        let(:rate_limiter_rate) { nil }
        let(:sampling_priority) { -1 }

        it "derives values for the drop decision" do
          is_expected.to have_attributes(random_value: "e12914a9a8771c", threshold: "e6666666666668")
        end
      end
    end

    context "when the 56-bit threshold would reverse a Datadog keep" do
      let(:trace_id) { 263811222310854400 }

      it "moves the random value to the threshold" do
        is_expected.to have_attributes(
          random_value: "e6666666666668",
          threshold: "e6666666666668"
        )
      end
    end

    context "when the 56-bit threshold would reverse a Datadog drop" do
      let(:trace_id) { 5401449561355763072 }
      let(:applied_rate) { 0.05 }
      let(:rate_limiter_rate) { nil }
      let(:sampling_priority) { 0 }

      it "moves the random value below the threshold" do
        is_expected.to have_attributes(
          random_value: "f333333333332f",
          threshold: "f333333333333"
        )
      end
    end

    context "with an inherited sampling priority but no ot values" do
      let(:distributed_sampling_priority) { true }

      it "does not create ot values" do
        expect(resolved.build).to be_empty
      end
    end

    context "without an applied rate" do
      let(:applied_rate) { nil }

      it "does not create ot values" do
        expect(resolved.build).to be_empty
      end
    end
  end

  describe ".from_tracestate_member" do
    subject(:extracted) { described_class.from_tracestate_member(value) }

    let(:value) { "rv:f972474538efff;th:8" }

    it "parses the random value and threshold" do
      is_expected.to have_attributes(
        random_value: "f972474538efff",
        threshold: "8",
        unknown_fields: nil
      )
    end

    context "with unknown fields" do
      let(:value) { "th:8;future:x;more:y" }

      it "preserves them" do
        is_expected.to have_attributes(
          random_value: nil,
          threshold: "8",
          unknown_fields: "future:x;more:y;"
        )
      end
    end

    ["th:", "th:xyz", "th:E6666666666668", "th:f00000000000000"].each do |member|
      context "with malformed #{member}" do
        let(:value) { "rv:f972474538efff;#{member}" }

        it "ignores the threshold" do
          is_expected.to have_attributes(random_value: "f972474538efff", threshold: nil)
        end
      end
    end

    ["rv:", "rv:xyz", "rv:f972474538eff", "rv:f972474538efff0"].each do |member|
      context "with malformed #{member}" do
        let(:value) { "#{member};th:8" }

        it "ignores the random value" do
          is_expected.to have_attributes(random_value: nil, threshold: "8")
        end
      end
    end
  end
end
