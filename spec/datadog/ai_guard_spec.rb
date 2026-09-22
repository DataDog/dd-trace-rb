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
    let(:message) { described_class.message(role: :user, content: "Hello") }

    it "returns a message with the given role and content" do
      aggregate_failures "returned message" do
        expect(message).to be_a(Datadog::AIGuard::Evaluation::Message)
        expect(message.role).to eq(:user)
        expect(message.content).to eq("Hello")
      end
    end

    context "when content and tool calls are provided" do
      let(:tool_calls) { [described_class.tool_call(name: "git", id: "git-1", arguments: {})] }
      let(:message) do
        described_class.message(
          role: :assistant,
          content: "Running git",
          tool_calls: tool_calls
        )
      end

      it "returns a message with the complete canonical shape" do
        aggregate_failures "returned message" do
          expect(message.content).to eq("Running git")
          expect(message.tool_calls).to eq(tool_calls)
        end
      end
    end

    context "when a numeric tool call id is provided" do
      let(:message) { described_class.message(role: :tool, content: "Done", tool_call_id: 42) }

      it { expect(message.tool_call_id).to eq("42") }
    end
  end

  describe ".tool_call" do
    context "when arguments are a string" do
      let(:tool_call) do
        described_class.tool_call(name: "git", id: "git-1", arguments: '{"command":"commit"}')
      end

      it "returns a tool call with the given attributes" do
        aggregate_failures "returned tool call" do
          expect(tool_call).to be_a(Datadog::AIGuard::Evaluation::ToolCall)
          expect(tool_call.id).to eq("git-1")
          expect(tool_call.tool_name).to eq("git")
          expect(tool_call.arguments).to eq('{"command":"commit"}')
        end
      end
    end

    context "when arguments are a hash" do
      let(:tool_call) do
        described_class.tool_call(name: "git", id: "git-1", arguments: {"command" => "commit"})
      end

      it { expect(tool_call.arguments).to eq('{"command":"commit"}') }
    end

    context "when the id is numeric" do
      let(:tool_call) { described_class.tool_call(name: "git", id: 42, arguments: {}) }

      it { expect(tool_call.id).to eq("42") }
    end

    context "when arguments are neither a string nor a hash" do
      it "raises an ArgumentError" do
        expect {
          described_class.tool_call(name: "git", id: "git-1", arguments: [])
        }.to raise_error(ArgumentError, "Tool call arguments must be a String or Hash")
      end
    end
  end

  describe ".assistant" do
    let(:tool_calls) do
      [
        described_class.tool_call(name: "git", id: "git-1", arguments: {}),
        described_class.tool_call(name: "notify", id: "notify-1", arguments: {})
      ]
    end
    let(:message) { described_class.assistant(content: "Running git", tool_calls: tool_calls) }

    it "returns an assistant message" do
      aggregate_failures "returned message" do
        expect(message.role).to eq(:assistant)
        expect(message.content).to eq("Running git")
        expect(message.tool_calls).to eq(tool_calls)
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
