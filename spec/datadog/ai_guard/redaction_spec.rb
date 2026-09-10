# frozen_string_literal: true

require "datadog/ai_guard/redaction"

RSpec.describe Datadog::AIGuard::Redaction do
  describe ".perform" do
    subject(:result) { described_class.perform(messages, replacements: replacements) }

    context "when the target is string content" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "My SSN is <REDACTED>",
          },
        ]
      end

      it "replaces string content with the backend value" do
        aggregate_failures "successful string content redaction" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :user, content: "My SSN is <REDACTED>"},
          ])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(0)
        end
      end
    end

    context "when the replacement is an empty string" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "",
          },
        ]
      end

      it "removes the content" do
        aggregate_failures "successful empty-string redaction" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :user, content: ""},
          ])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(0)
        end
      end
    end

    context "when the target is a multimodal text part" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: [
              Datadog::AIGuard::Evaluation::ContentPart::Text.new("Card 4111111111111111"),
              Datadog::AIGuard::Evaluation::ContentPart::ImageURL.new("https://example.com/image.png"),
            ]
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content[0].text",
            "replacement" => "Card <REDACTED>",
          },
        ]
      end

      it "replaces the text and preserves the other content parts" do
        aggregate_failures "successful multimodal text redaction" do
          expect(result.messages.map(&:to_h)).to eq([
            {
              role: :user,
              content: [
                {type: "text", text: "Card <REDACTED>"},
                {type: "image_url", image_url: {url: "https://example.com/image.png"}},
              ],
            },
          ])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(0)
        end
      end
    end

    context "when the target is a tool call argument string" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :assistant,
            tool_call: Datadog::AIGuard::Evaluation::ToolCall.new(
              "send_email",
              id: "call-1",
              arguments: '{"to":"person@example.com"}'
            )
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].tool_calls[0].function.arguments",
            "replacement" => '{"to":"<REDACTED>"}',
          },
        ]
      end

      it "replaces the complete argument string" do
        aggregate_failures "successful tool argument redaction" do
          expect(result.messages.map(&:to_h)).to eq([
            {
              role: :assistant,
              tool_calls: [
                {
                  id: "call-1",
                  function: {
                    name: "send_email",
                    arguments: '{"to":"<REDACTED>"}',
                  },
                },
              ],
            },
          ])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(0)
        end
      end
    end

    context "when replacements target multiple messages" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :system,
            content: "Contact ops@example.com"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :assistant,
            content: "How can I help?"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "Contact <REDACTED>",
          },
          {
            "path" => "messages[2].content",
            "replacement" => "My SSN is <REDACTED>",
          },
        ]
      end

      it "applies every replacement across the complete conversation" do
        aggregate_failures "successful full-context redaction" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :system, content: "Contact <REDACTED>"},
            {role: :assistant, content: "How can I help?"},
            {role: :user, content: "My SSN is <REDACTED>"},
          ])
          expect(result.applied).to eq(2)
          expect(result.failures).to eq(0)
        end
      end
    end

    context "when there are no replacements" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "Nothing sensitive"
          ),
        ]
      end
      let(:replacements) { [] }

      it { expect(result.messages).to equal(messages) }
    end

    context "when one of multiple messages is redacted" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :system,
            content: "You are a helpful assistant"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[1].content",
            "replacement" => "My SSN is <REDACTED>",
          },
        ]
      end

      it "copies the array and changed message without modifying or copying the unchanged message" do
        aggregate_failures "copy-on-write message redaction" do
          expect(result.messages).not_to equal(messages)
          expect(result.messages[0]).to equal(messages[0])
          expect(result.messages[1]).not_to equal(messages[1])
          expect(messages.map(&:to_h)).to eq([
            {role: :system, content: "You are a helpful assistant"},
            {role: :user, content: "My SSN is 123-45-6789"},
          ])
        end
      end
    end

    context "when one part of multimodal content is redacted" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: [
              Datadog::AIGuard::Evaluation::ContentPart::Text.new("Card 4111111111111111"),
              Datadog::AIGuard::Evaluation::ContentPart::ImageURL.new("https://example.com/image.png"),
            ]
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content[0].text",
            "replacement" => "Card <REDACTED>",
          },
        ]
      end

      it "copies the changed text while preserving the caller's content and unchanged image" do
        aggregate_failures "copy-on-write multimodal redaction" do
          expect(result.messages[0].content).not_to equal(messages[0].content)
          expect(result.messages[0].content[0]).not_to equal(messages[0].content[0])
          expect(result.messages[0].content[1]).to equal(messages[0].content[1])
          expect(messages[0].content[0].text).to eq("Card 4111111111111111")
        end
      end
    end

    context "when tool call arguments are redacted" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :assistant,
            tool_call: Datadog::AIGuard::Evaluation::ToolCall.new(
              "send_email",
              id: "call-1",
              arguments: '{"to":"person@example.com"}'
            )
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].tool_calls[0].function.arguments",
            "replacement" => '{"to":"<REDACTED>"}',
          },
        ]
      end

      it "copies the message and tool call without modifying the caller's arguments" do
        aggregate_failures "copy-on-write tool argument redaction" do
          expect(result.messages[0]).not_to equal(messages[0])
          expect(result.messages[0].tool_call).not_to equal(messages[0].tool_call)
          expect(messages[0].tool_call.arguments).to eq('{"to":"person@example.com"}')
        end
      end
    end

    context "when replacements is not an array" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        {
          "path" => "messages[0].content",
          "replacement" => "My SSN is <REDACTED>",
        }
      end

      it "skips the payload and records one failure" do
        aggregate_failures "invalid replacements collection" do
          expect(result.messages).to equal(messages)
          expect(result.applied).to eq(0)
          expect(result.failures).to eq(1)
          expect(result).not_to be_redacted
        end
      end
    end

    context "when replacement entries are malformed" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          nil,
          {"replacement" => "My SSN is <REDACTED>"},
          {"path" => "", "replacement" => "My SSN is <REDACTED>"},
          {"path" => :content, "replacement" => "My SSN is <REDACTED>"},
          {"path" => "messages[0].content"},
          {"path" => "messages[0].content", "replacement" => 123},
        ]
      end

      it "skips every malformed entry and records each failure" do
        aggregate_failures "malformed replacement entries" do
          expect(result.messages).to equal(messages)
          expect(result.applied).to eq(0)
          expect(result.failures).to eq(6)
          expect(result).not_to be_redacted
        end
      end
    end

    context "when replacement paths do not resolve" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          {"path" => "messages[-1].content", "replacement" => "redacted"},
          {"path" => "messages.content", "replacement" => "redacted"},
          {"path" => "items[0].content", "replacement" => "redacted"},
          {"path" => "messages[2].content", "replacement" => "redacted"},
          {"path" => "messages[0].unknown", "replacement" => "redacted"},
        ]
      end

      it "skips every invalid path and records each failure" do
        aggregate_failures "unresolvable replacement paths" do
          expect(result.messages).to equal(messages)
          expect(result.applied).to eq(0)
          expect(result.failures).to eq(5)
          expect(result).not_to be_redacted
        end
      end
    end

    context "when replacement paths target unsupported or non-string values" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: [
              Datadog::AIGuard::Evaluation::ContentPart::Text.new("Card 4111111111111111"),
              Datadog::AIGuard::Evaluation::ContentPart::ImageURL.new("https://example.com/image.png"),
            ]
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :assistant,
            tool_call: Datadog::AIGuard::Evaluation::ToolCall.new(
              "send_email",
              id: "call-1",
              arguments: {to: "person@example.com"}
            )
          ),
        ]
      end
      let(:replacements) do
        [
          {"path" => "messages[0].content", "replacement" => "redacted"},
          {"path" => "messages[0].content[1].image_url.url", "replacement" => "redacted"},
          {"path" => "messages[1].tool_calls[0].function.arguments", "replacement" => "redacted"},
        ]
      end

      it "skips every non-redactable target and records each failure" do
        aggregate_failures "unsupported and non-string targets" do
          expect(result.messages).to equal(messages)
          expect(result.applied).to eq(0)
          expect(result.failures).to eq(3)
          expect(result).not_to be_redacted
        end
      end
    end

    context "when a path has duplicate identical replacements" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
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

      it "applies the replacement once without recording a failure" do
        aggregate_failures "identical duplicate replacement" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :user, content: "My SSN is <REDACTED>"},
          ])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(0)
        end
      end
    end

    context "when a path has conflicting replacements" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "Email person@example.com"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "My SSN is <REDACTED>",
          },
          {
            "path" => "messages[0].content",
            "replacement" => "My SSN is <PRIVATE>",
          },
          {
            "path" => "messages[1].content",
            "replacement" => "Email <REDACTED>",
          },
        ]
      end

      it "skips the conflicting path while applying independent replacements" do
        aggregate_failures "conflicting replacement isolation" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :user, content: "My SSN is 123-45-6789"},
            {role: :user, content: "Email <REDACTED>"},
          ])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(1)
        end
      end
    end

    context "when valid and unresolvable replacements are mixed" do
      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :system,
            content: "Contact ops@example.com"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "Contact <REDACTED>",
          },
          {
            "path" => "messages[4].content",
            "replacement" => "redacted",
          },
          {
            "path" => "messages[1].content",
            "replacement" => "My SSN is <REDACTED>",
          },
        ]
      end

      it "applies every valid replacement and records the invalid path" do
        aggregate_failures "partial fail-safe redaction" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :system, content: "Contact <REDACTED>"},
            {role: :user, content: "My SSN is <REDACTED>"},
          ])
          expect(result.applied).to eq(2)
          expect(result.failures).to eq(1)
        end
      end
    end

    context "when applying the second replacement raises" do
      before { allow(messages[1]).to receive(:with_content).and_raise(StandardError) }

      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "Contact ops@example.com"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :assistant,
            content: "How can I help?"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "Contact <REDACTED>",
          },
          {
            "path" => "messages[1].content",
            "replacement" => "My SSN is <REDACTED>",
          },
        ]
      end

      it "preserves the successful redaction and leaves the remaining messages unchanged" do
        aggregate_failures "partial redaction after an unexpected replacement failure" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :user, content: "Contact <REDACTED>"},
            {role: :user, content: "My SSN is 123-45-6789"},
            {role: :assistant, content: "How can I help?"},
          ])
          expect(result.messages[1]).to equal(messages[1])
          expect(result.messages[2]).to equal(messages[2])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(1)
        end
      end
    end

    context "when applying the first replacement raises" do
      before { allow(messages[0]).to receive(:with_content).and_raise(StandardError) }

      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "Contact ops@example.com"
          ),
          Datadog::AIGuard::Evaluation::Message.new(
            role: :user,
            content: "My SSN is 123-45-6789"
          ),
        ]
      end
      let(:replacements) do
        [
          {
            "path" => "messages[0].content",
            "replacement" => "Contact <REDACTED>",
          },
          {
            "path" => "messages[1].content",
            "replacement" => "My SSN is <REDACTED>",
          },
        ]
      end

      it "leaves the failed message unchanged and applies the remaining replacement" do
        aggregate_failures "partial redaction after the first replacement fails" do
          expect(result.messages.map(&:to_h)).to eq([
            {role: :user, content: "Contact ops@example.com"},
            {role: :user, content: "My SSN is <REDACTED>"},
          ])
          expect(result.messages[0]).to equal(messages[0])
          expect(result.applied).to eq(1)
          expect(result.failures).to eq(1)
        end
      end
    end
  end

  describe ".skip" do
    subject(:result) { described_class.skip(messages) }

    context "when messages are provided" do
      let(:messages) { [Object.new] }

      it "returns the original messages without performing redaction" do
        aggregate_failures "skipped redaction result" do
          expect(result.messages).to equal(messages)
          expect(result.applied).to eq(0)
          expect(result.failures).to eq(0)
          expect(result).not_to be_performed
          expect(result).not_to be_redacted
        end
      end
    end
  end
end
