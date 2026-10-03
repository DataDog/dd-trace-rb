# frozen_string_literal: true

require "datadog/ai_guard/evaluation/response"

RSpec.describe Datadog::AIGuard::Evaluation::Response do
  subject(:response) { described_class.new(raw_response) }

  let(:raw_response) do
    {
      "data" => {
        "attributes" => {
          "action" => "DENY",
          "reason" => "Some reason",
          "tags" => ["some", "tags"],
          "sds_findings" => [
            {
              "rule_display_name" => "Credit Card Number",
              "rule_tag" => "credit_card",
              "category" => "pii",
              "matched_text" => "4111111111111111",
              "location" => {
                "start_index" => 0,
                "end_index_exclusive" => 26,
                "path" => "messages[0].content[0].text",
              },
            },
          ],
          "tag_probs" => {"some" => 0.95, "tags" => 0.1},
          "is_blocking_enabled" => false,
          "redaction_replacements" => [
            {
              "path" => "messages[0].content",
              "replacement" => "Card: <REDACTED>",
            },
          ],
        },
      },
    }
  end

  describe ".new" do
    context "when a required response key is missing" do
      it "raises an AI Guard client error" do
        expect { described_class.new({}) }.to raise_error(
          Datadog::AIGuard::AIGuardClientError,
          "Missing key: \"data\""
        )
      end
    end
  end

  describe "#action" do
    it { expect(response.action).to eq("DENY") }
  end

  describe "#reason" do
    it { expect(response.reason).to eq("Some reason") }
  end

  describe "#tags" do
    it { expect(response.tags).to eq(["some", "tags"]) }
  end

  describe "#sds_findings" do
    it "returns the findings from the response" do
      expect(response.sds_findings).to eq([
        {
          "rule_display_name" => "Credit Card Number",
          "rule_tag" => "credit_card",
          "category" => "pii",
          "matched_text" => "4111111111111111",
          "location" => {
            "start_index" => 0,
            "end_index_exclusive" => 26,
            "path" => "messages[0].content[0].text",
          },
        },
      ])
    end

    context "when findings are absent" do
      let(:raw_response) do
        {
          "data" => {
            "attributes" => {
              "action" => "DENY",
              "reason" => "Some reason",
              "tags" => ["some", "tags"],
              "tag_probs" => {"some" => 0.95, "tags" => 0.1},
              "is_blocking_enabled" => false,
            },
          },
        }
      end

      it { expect(response.sds_findings).to eq([]) }
    end
  end

  describe "#tag_probabilities" do
    it { expect(response.tag_probabilities).to eq("some" => 0.95, "tags" => 0.1) }
  end

  describe "#blocking_enabled?" do
    it { expect(response).not_to be_blocking_enabled }
  end

  describe "#redaction_replacements" do
    it "returns replacements from the response" do
      expect(response.redaction_replacements).to eq([
        {
          "path" => "messages[0].content",
          "replacement" => "Card: <REDACTED>",
        },
      ])
    end

    context "when replacements are absent" do
      before { raw_response.fetch("data").fetch("attributes").delete("redaction_replacements") }

      it { expect(response.redaction_replacements).to eq([]) }
    end
  end
end
