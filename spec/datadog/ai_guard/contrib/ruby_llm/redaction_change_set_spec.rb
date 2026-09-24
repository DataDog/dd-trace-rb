# frozen_string_literal: true

require "ruby_llm"
require "datadog/ai_guard"
require "datadog/ai_guard/contrib/ruby_llm/redaction_change_set"

require "spec_helper"

RSpec.describe Datadog::AIGuard::Contrib::RubyLLM::RedactionChangeSet do
  describe "#apply_to" do
    context "when redacted tool-call arguments are invalid JSON" do
      subject(:apply_to) { change_set.apply_to(message) }

      let(:change_set) { described_class.new(original_message, redacted_message) }
      let(:original_message) do
        Datadog::AIGuard.message(role: :assistant, tool_calls: [original_tool_call])
      end
      let(:redacted_message) do
        original_message.with_tool_calls([original_tool_call.with_arguments("invalid")])
      end
      let(:original_tool_call) do
        Datadog::AIGuard.tool_call(name: "shell", id: "call_1", arguments: '{"command":"ls /"}')
      end
      let(:message) do
        RubyLLM::Message.new(
          role: :assistant,
          content: "Running the command",
          tool_calls: {"call_1" => tool_call}
        )
      end
      let(:tool_call) do
        RubyLLM::ToolCall.new(id: "call_1", name: "shell", arguments: {"command" => "ls /"})
      end

      it "raises without changing the original tool call" do
        expect { apply_to }.to raise_error(JSON::ParserError)
        expect(tool_call.arguments).to eq("command" => "ls /")
      end
    end
  end
end
