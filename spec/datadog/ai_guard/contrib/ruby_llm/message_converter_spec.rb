# frozen_string_literal: true

require "ruby_llm"
require "datadog/ai_guard"
require "datadog/ai_guard/contrib/ruby_llm/message_converter"

require "spec_helper"

RSpec.describe Datadog::AIGuard::Contrib::RubyLLM::MessageConverter do
  describe ".convert" do
    let(:message) do
      RubyLLM::Message.new(
        role: :assistant,
        content: "Running the command",
        tool_calls: {
          "tool_call_1" => RubyLLM::ToolCall.new(
            id: "tool_call_1",
            name: "shell",
            arguments: arguments
          )
        }
      )
    end

    context "when tool-call arguments can be encoded as JSON" do
      let(:arguments) { {"command" => "ls /"} }

      it "serializes the arguments as JSON" do
        converted_message = described_class.convert([message]).first
        expect(converted_message.tool_call.arguments).to eq('{"command":"ls /"}')
      end
    end

    context "when tool-call arguments cannot be encoded as JSON" do
      let(:arguments) do
        recursive = {}
        recursive["recursive"] = recursive
        recursive
      end

      it { expect(described_class.convert([message])).to be_nil }
    end
  end
end
