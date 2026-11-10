# frozen_string_literal: true

require "datadog/ai_guard/component"

RSpec.describe Datadog::AIGuard::Evaluation::Outcome do
  describe "#block?" do
    let(:outcome) do
      described_class.new(
        result: result,
        redaction: redaction,
        blocking_enabled: decision.fetch(:blocking_enabled),
        extra_tags: nil,
        extra_metastruct: nil,
      )
    end
    let(:result) do
      instance_double(
        Datadog::AIGuard::Evaluation::Result,
        deny?: decision.fetch(:deny),
        abort?: decision.fetch(:abort),
      )
    end
    let(:redaction) { instance_double(Datadog::AIGuard::Redaction::Result) }

    context "when action is ALLOW and blocking is enabled" do
      let(:decision) { {blocking_enabled: true, deny: false, abort: false} }

      it { expect(outcome).not_to be_block }
    end

    context "when action is ALLOW and blocking is disabled" do
      let(:decision) { {blocking_enabled: false, deny: false, abort: false} }

      it { expect(outcome).not_to be_block }
    end

    context "when action is DENY and blocking is enabled" do
      let(:decision) { {blocking_enabled: true, deny: true, abort: false} }

      it { expect(outcome).to be_block }
    end

    context "when action is DENY and blocking is disabled" do
      let(:decision) { {blocking_enabled: false, deny: true, abort: false} }

      it { expect(outcome).not_to be_block }
    end

    context "when action is ABORT and blocking is enabled" do
      let(:decision) { {blocking_enabled: true, deny: false, abort: true} }

      it { expect(outcome).to be_block }
    end

    context "when action is ABORT and blocking is disabled" do
      let(:decision) { {blocking_enabled: false, deny: false, abort: true} }

      it { expect(outcome).not_to be_block }
    end
  end

  describe "backend extras" do
    let(:outcome) do
      described_class.new(
        result: instance_double(Datadog::AIGuard::Evaluation::Result),
        redaction: instance_double(Datadog::AIGuard::Redaction::Result),
        blocking_enabled: false,
        extra_tags: extra_tags,
        extra_metastruct: extra_metastruct,
      )
    end

    context "when collections are absent" do
      let(:extra_tags) { nil }
      let(:extra_metastruct) { nil }

      it "returns empty hashes" do
        expect(outcome.extra_tags).to eq({})
        expect(outcome.extra_metastruct).to eq({})
      end
    end

    context "when collections are not arrays" do
      let(:extra_tags) { {"ai_guard.policy" => "example"} }
      let(:extra_metastruct) { {"policy_match" => {"rule" => "example"}} }

      it "returns empty hashes" do
        expect(outcome.extra_tags).to eq({})
        expect(outcome.extra_metastruct).to eq({})
      end
    end

    context "when collections contain valid, malformed, reserved and duplicate entries" do
      let(:extra_tags) do
        [
          {"key" => "ai_guard.evaluate_id", "value" => "evaluation-123"},
          {"key" => "custom_context.note", "value" => ""},
          nil,
          {"value" => "missing key"},
          {"key" => "", "value" => "empty key"},
          {"key" => 1, "value" => "numeric key"},
          {"key" => "bad.number", "value" => 42},
          {"key" => "bad.nil", "value" => nil},
          {"key" => "ai_guard.action", "value" => "forged"},
          {"key" => "_dd.custom", "value" => "forged"},
          {"key" => "custom_context.note", "value" => 42},
        ]
      end
      let(:extra_metastruct) do
        [
          {"key" => "policy_match", "value" => {"rule" => "example", "matches" => [], "note" => nil}},
          {"key" => "flag", "value" => false},
          {"key" => "empty", "value" => []},
          "not an object",
          {"key" => "bad.nil", "value" => nil},
          {"key" => "messages", "value" => "forged"},
          {"key" => "flag", "value" => nil},
        ]
      end

      it "keeps only valid non-reserved entries with their exact keys" do
        expect(outcome.extra_tags).to eq(
          "ai_guard.evaluate_id" => "evaluation-123",
          "custom_context.note" => "",
        )
        expect(outcome.extra_metastruct).to eq(
          "policy_match" => {"rule" => "example", "matches" => [], "note" => nil},
          "flag" => false,
          "empty" => [],
        )
      end
    end

    context "when metadata contains integers outside the MessagePack range" do
      let(:extra_tags) { nil }
      let(:nested_value) do
        {
          "values" => [2**64, {"minimum" => -(2**63) - 1}],
          "bounds" => [-(2**63), (2**64) - 1],
          "unchanged" => [42, 0.5, "text", true, false, nil],
        }
      end
      let(:extra_metastruct) { [{"key" => "nested", "value" => nested_value}] }

      it "clamps integers recursively without modifying the input" do
        expect(outcome.extra_metastruct).to eq(
          "nested" => {
            "values" => [(2**64) - 1, {"minimum" => -(2**63)}],
            "bounds" => [-(2**63), (2**64) - 1],
            "unchanged" => [42, 0.5, "text", true, false, nil],
          },
        )
        expect(nested_value.fetch("values")).to eq([2**64, {"minimum" => -(2**63) - 1}])
      end
    end
  end
end
