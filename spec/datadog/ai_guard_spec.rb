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
    end

    context "when AI Guard is disabled" do
      include_context :ai_guard_disabled
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
