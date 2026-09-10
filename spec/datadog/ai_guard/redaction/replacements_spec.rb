# frozen_string_literal: true

require "datadog/ai_guard/redaction/replacements"

RSpec.describe Datadog::AIGuard::Redaction::Replacements do
  describe "#each" do
    subject(:replacements) { described_class.new(raw_replacements) }

    context "when replacements use every supported path" do
      let(:raw_replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "",
          },
          {
            "path" => "messages[1].content[2].text",
            "replacement" => "Card <REDACTED>",
          },
          {
            "path" => "messages[2].tool_calls[000].function.arguments",
            "replacement" => "{}",
          },
        ]
      end

      it "yields normalized replacements in input order" do
        aggregate_failures "supported replacement path normalization" do
          expect(replacements.failures).to eq(0)
          expect(replacements.each.to_a).to eq([
            [[0, :content], ""],
            [[1, :text, 2], "Card <REDACTED>"],
            [[2, :arguments], "{}"],
          ])
        end
      end
    end

    context "when the payload is empty" do
      subject(:replacements) { described_class.new([]) }

      it "returns no replacements without recording a failure" do
        aggregate_failures "empty replacements collection" do
          expect(replacements.each.to_a).to be_empty
          expect(replacements.failures).to eq(0)
        end
      end
    end

    context "when the payload is not an array" do
      subject(:replacements) do
        described_class.new(
          "path" => "messages[0].content",
          "replacement" => "<REDACTED>"
        )
      end

      it "returns no replacements and records one failure" do
        aggregate_failures "invalid replacements collection" do
          expect(replacements.each.to_a).to be_empty
          expect(replacements.failures).to eq(1)
        end
      end
    end

    context "when replacement entries are malformed" do
      let(:raw_replacements) do
        [
          nil,
          {"replacement" => "<REDACTED>"},
          {"path" => "", "replacement" => "<REDACTED>"},
          {"path" => :content, "replacement" => "<REDACTED>"},
          {"path" => "messages[0].content"},
          {"path" => "messages[0].content", "replacement" => 123},
        ]
      end

      it "skips every malformed entry and records each failure" do
        aggregate_failures "malformed replacement entries" do
          expect(replacements.each.to_a).to be_empty
          expect(replacements.failures).to eq(6)
        end
      end
    end

    context "when replacement paths are unsupported" do
      let(:raw_replacements) do
        [
          {"path" => "messages[-1].content", "replacement" => "<REDACTED>"},
          {"path" => "messages.content", "replacement" => "<REDACTED>"},
          {"path" => "items[0].content", "replacement" => "<REDACTED>"},
          {"path" => "messages[0].unknown", "replacement" => "<REDACTED>"},
          {"path" => "messages[0].tool_calls[1].function.arguments", "replacement" => "{}"},
        ]
      end

      it "skips every unsupported path and records each failure" do
        aggregate_failures "unsupported replacement paths" do
          expect(replacements.each.to_a).to be_empty
          expect(replacements.failures).to eq(5)
        end
      end
    end

    context "when a path has duplicate identical replacements" do
      let(:raw_replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "My SSN is <REDACTED>",
          },
          {
            "path" => "messages[0].content",
            "replacement" => "My SSN is <REDACTED>",
          },
        ]
      end

      it "keeps one replacement without recording a failure" do
        aggregate_failures "identical duplicate replacement" do
          expect(replacements.failures).to eq(0)
          expect(replacements.each.to_a).to eq([
            [[0, :content], "My SSN is <REDACTED>"],
          ])
        end
      end
    end

    context "when equivalent paths have conflicting replacements" do
      let(:raw_replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "My SSN is <REDACTED>",
          },
          {
            "path" => "messages[00].content",
            "replacement" => "My SSN is <PRIVATE>",
          },
          {
            "path" => "messages[0].content",
            "replacement" => "My SSN is <REDACTED>",
          },
          {
            "path" => "messages[1].content",
            "replacement" => "Email <REDACTED>",
          },
        ]
      end

      it "removes the conflicted path and preserves independent replacements" do
        aggregate_failures "conflicting replacement isolation" do
          expect(replacements.failures).to eq(1)
          expect(replacements.each.to_a).to eq([
            [[1, :content], "Email <REDACTED>"],
          ])
        end
      end
    end
  end
end
