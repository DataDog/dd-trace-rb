# frozen_string_literal: true

require "spec_helper"
require "datadog/ai_guard"

RSpec.describe Datadog::AIGuard do
  shared_context :ai_guard_enabled do
    before do
      Datadog.configure { |c| c.ai_guard.enabled = true }
    end

    after do
      Datadog.configuration.reset!
    end
  end

  shared_context :ai_guard_disabled do
    before do
      Datadog.configure { |c| c.ai_guard.enabled = false }
    end

    after do
      Datadog.configuration.reset!
    end
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

  describe ".api_client" do
    context "when AI Guard is enabled" do
      include_context :ai_guard_enabled

      it "returns an instance of APIClient" do
        expect(described_class.api_client).to be_a(Datadog::AIGuard::APIClient)
      end
    end

    context "when AI Guard is disabled" do
      include_context :ai_guard_disabled

      it "returns nil" do
        expect(described_class.api_client).to be_nil
      end
    end
  end

  describe ".evaluate" do
    context "when AI Guard is enabled" do
      include_context :ai_guard_enabled

      let(:messages) do
        [
          Datadog::AIGuard::Evaluation::Message.new(role: :system, content: "Hello")
        ]
      end

      before do
        Datadog.configuration.ai_guard.enabled = true

        WebMock.enable!

        stub_request(:post, "https://app.datadoghq.com/api/v2/ai-guard/evaluate")
          .to_return do |request|
            {
              status: 200,
              body: raw_response.to_json,
              headers: {"Content-Type" => "application/json"}
            }
          end
      end

      after do
        Datadog.configuration.reset!

        WebMock.reset!
        WebMock.disable!
      end

      context "when result is ALLOW" do
        let(:raw_response) do
          {
            "data" => {
              "attributes" => {
                "action" => "ALLOW",
                "reason" => "No rule match",
                "tags" => [],
                "is_blocking_enabled": false
              }
            }
          }
        end

        it "returns Datadog::AIGuard::Evaluation::Result when allow_raise is set to false" do
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
                "is_blocking_enabled": true
              }
            }
          }
        end

        it "raises Datadog::AIGuard::Interrupt when allow_raise is set to true" do
          expect { described_class.evaluate(*messages, allow_raise: true) }.to raise_error(
            Datadog::AIGuard::Interrupt
          )
        end

        it "returns Datadog::AIGuard::Evaluation::Result when allow_raise is set to false" do
          result = described_class.evaluate(*messages)

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
          Datadog::AIGuard::Evaluation::Message.new(role: :system, content: "Hello")
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
    it "returns a message with the given role and content" do
      message = described_class.message(role: :user, content: "Hello")

      aggregate_failures "returned message" do
        expect(message).to be_a(Datadog::AIGuard::Evaluation::Message)
        expect(message.role).to eq(:user)
        expect(message.content).to eq("Hello")
      end
    end
  end

  describe ".assistant" do
    it "returns a message containing a tool call" do
      message = described_class.assistant(tool_name: "git", id: "git-1", arguments: "commit -m 'Some message'")

      aggregate_failures "returned message" do
        expect(message).to be_a(Datadog::AIGuard::Evaluation::Message)
        expect(message.role).to eq(:assistant)
        expect(message.content).to be_nil

        expect(message.tool_call).to be_a(Datadog::AIGuard::Evaluation::ToolCall)
        expect(message.tool_call.id).to eq("git-1")
        expect(message.tool_call.tool_name).to eq("git")
        expect(message.tool_call.arguments).to eq("commit -m 'Some message'")
      end
    end
  end

  describe ".tool" do
    it "returns a message with :tool role and a given tool call id and content" do
      message = described_class.tool(tool_call_id: "git-1", content: "Some output")

      aggregate_failures "returned message" do
        expect(message).to be_a(Datadog::AIGuard::Evaluation::Message)
        expect(message.role).to eq(:tool)
        expect(message.content).to eq("Some output")
        expect(message.tool_call_id).to eq("git-1")
      end
    end
  end
end
