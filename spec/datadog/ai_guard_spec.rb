# frozen_string_literal: true

require "spec_helper"
require "datadog/ai_guard"

RSpec.describe Datadog::AIGuard do
  shared_context :ai_guard_enabled do
    before { Datadog.configure { |c| c.ai_guard.enabled = true } }
    after { Datadog.configuration.reset! }
  end

  shared_context :ai_guard_disabled do
    before { Datadog.configure { |c| c.ai_guard.enabled = false } }
    after { Datadog.configuration.reset! }
  end

  describe ".enabled?" do
    context "when AI Guard is enabled" do
      include_context :ai_guard_enabled

      it { expect(described_class.enabled?).to be(true) }
    end

    context "when AI Guard is disabled" do
      include_context :ai_guard_disabled

      it { expect(described_class.enabled?).to be(false) }
    end
  end

  describe ".http_client" do
    context "when AI Guard is enabled" do
      include_context :ai_guard_enabled

      it { expect(described_class.http_client).to be_a(Datadog::AIGuard::HTTPClient) }
    end

    context "when AI Guard is disabled" do
      include_context :ai_guard_disabled

      it { expect(described_class.http_client).to be_nil }
    end
  end

  describe ".evaluate" do
    context "when AI Guard is enabled", webmock: true do
      before do
        Datadog.configuration.ai_guard.enabled = true

        stub_request(:post, "https://app.datadoghq.com/api/v2/ai-guard/evaluate")
          .to_return do |request|
            {
              status: 200,
              body: raw_response.to_json,
              headers: {"Content-Type" => "application/json"},
            }
          end
      end

      after { Datadog.configuration.reset! }

      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(role: :system, content: "Hello"),
        ]
      end

      context "when result is ALLOW" do
        let(:raw_response) do
          {
            "data" => {
              "attributes" => {
                "action" => "ALLOW",
                "reason" => "No rule match",
                "tags" => [],
                "tag_probs" => {},
                "is_blocking_enabled" => false,
              },
            },
          }
        end

        it "returns Datadog::AIGuard::Evaluation::Result when allow_raise is set to true" do
          result = described_class.evaluate(*messages, allow_raise: true)

          aggregate_failures "result properties" do
            expect(result).to be_a(Datadog::AIGuard::Evaluation::Result)
            expect(result).to be_allow
            expect(result.reason).to eq("No rule match")
            expect(result.tags).to eq([])
          end
        end
      end

      context "when result is DENY and is_blocking_enabled is set to true in the response" do
        let(:raw_response) do
          {
            "data" => {
              "attributes" => {
                "action" => "DENY",
                "reason" => "Rule match",
                "tags" => ["indirect-prompt-injection"],
                "tag_probs" => {"indirect-prompt-injection" => 0.95},
                "is_blocking_enabled" => true,
              },
            },
          }
        end

        it "raises Datadog::AIGuard::AIGuardAbortError when allow_raise is set to true" do
          expect { described_class.evaluate(*messages, allow_raise: true) }.to raise_error(
            Datadog::AIGuard::AIGuardAbortError
          )
        end

        it "returns Datadog::AIGuard::Evaluation::Result when allow_raise is set to false" do
          result = described_class.evaluate(*messages, allow_raise: false)

          aggregate_failures "result properties" do
            expect(result).to be_a(Datadog::AIGuard::Evaluation::Result)
            expect(result).to be_deny
            expect(result.reason).to eq("Rule match")
            expect(result.tags).to eq(["indirect-prompt-injection"])
          end
        end
      end
    end

    context "when AI Guard is disabled" do
      include_context :ai_guard_disabled

      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(role: :system, content: "Hello"),
        ]
      end

      it "returns a no-op result" do
        result = described_class.evaluate(*messages)

        aggregate_failures "no-op result properties" do
          expect(result).to be_a(Datadog::AIGuard::Evaluation::NoOpResult)
          expect(result.action).to eq("ALLOW")
          expect(result.reason).not_to be_nil
          expect(result.tags).to eq([])

          expect(result).to be_allow
          expect(result).not_to be_deny
          expect(result).not_to be_abort
        end
      end
    end
  end

  describe ".message" do
    context "when string content is provided" do
      let(:message) { described_class.message(role: :user, content: "Hello") }

      it "returns a message with the given role and content" do
        aggregate_failures "returned message" do
          expect(message).to be_a(Datadog::AIGuard::Evaluation::Message)
          expect(message.role).to eq(:user)
          expect(message.content).to eq("Hello")
        end
      end
    end

    context "when content parts are built in a block" do
      let(:message) do
        described_class.message(role: :user) do |message_builder|
          message_builder.text("What's in this image?")
          message_builder.image_url("https://example.com/img.png")
        end
      end

      it "returns a message with multi-modal content" do
        aggregate_failures "returned message" do
          expect(message.role).to eq(:user)
          expect(message.content[0].to_h).to eq(type: "text", text: "What's in this image?")
          expect(message.content[1].to_h).to eq(
            type: "image_url", image_url: {url: "https://example.com/img.png"}
          )
        end
      end
    end

    context "when string content and block content parts are provided" do
      let(:message) do
        described_class.message(role: :user, content: "Hello") do |builder|
          builder.text("World")
        end
      end

      it "raises an ArgumentError" do
        expect { message }.to raise_error(ArgumentError, "Cannot combine content with content parts")
      end
    end
  end

  describe ".assistant" do
    context "when multiple tool calls are built in a block" do
      let(:message) do
        described_class.assistant(content: "Running tools") do |builder|
          builder.tool_call(name: "git", id: "git-1", arguments: {})
          builder.tool_call(name: "notify", id: "notify-1", arguments: {})
        end
      end

      it "returns an assistant message with the tool calls in insertion order" do
        aggregate_failures "returned message" do
          expect(message.role).to eq(:assistant)
          expect(message.content).to eq("Running tools")
          expect(message.tool_calls.map(&:tool_name)).to eq(["git", "notify"])
        end
      end
    end

    context "when a tool call is built in a block" do
      let(:message) do
        described_class.assistant(content: "Running git") do |message_builder|
          message_builder.tool_call(name: "git", id: "git-1", arguments: {command: "status"})
        end
      end

      it "returns an assistant message with string content and the tool call" do
        aggregate_failures "returned message" do
          expect(message.role).to eq(:assistant)
          expect(message.content).to eq("Running git")
          expect(message.tool_calls[0].tool_name).to eq("git")
          expect(message.tool_calls[0].id).to eq("git-1")
          expect(message.tool_calls[0].arguments).to eq('{"command":"status"}')
        end
      end
    end

    context "when content parts and a tool call are built in a block" do
      let(:message) do
        described_class.assistant do |message_builder|
          message_builder.text("Inspect this image")
          message_builder.image_url("https://example.com/img.png")
          message_builder.tool_call(name: "inspect", id: 42, arguments: {})
        end
      end

      it "returns an assistant message with the complete canonical shape" do
        aggregate_failures "returned message" do
          expect(message.content[0].to_h).to eq(type: "text", text: "Inspect this image")
          expect(message.content[1].to_h).to eq(
            type: "image_url", image_url: {url: "https://example.com/img.png"}
          )
          expect(message.tool_calls[0].tool_name).to eq("inspect")
          expect(message.tool_calls[0].id).to eq("42")
        end
      end
    end

    context "when tool call arguments are neither a string nor a hash" do
      let(:message) do
        described_class.assistant do |builder|
          builder.tool_call(name: "git", id: "git-1", arguments: [])
        end
      end

      it "raises an ArgumentError" do
        expect { message }.to raise_error(ArgumentError, "Tool call arguments must be a String or Hash")
      end
    end
  end

  describe ".tool" do
    let(:message) { described_class.tool(tool_call_id: "git-1", content: "Some output") }

    it "returns a message with :tool role and a given tool call id and content" do
      aggregate_failures "returned message" do
        expect(message).to be_a(Datadog::AIGuard::Evaluation::Message)
        expect(message.role).to eq(:tool)
        expect(message.content).to eq("Some output")
        expect(message.tool_call_id).to eq("git-1")
      end
    end

    context "when the tool call id is numeric" do
      let(:message) { described_class.tool(tool_call_id: 42, content: "Some output") }

      it { expect(message.tool_call_id).to eq("42") }
    end
  end
end
