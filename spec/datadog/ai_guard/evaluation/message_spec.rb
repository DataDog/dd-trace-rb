# frozen_string_literal: true

require 'datadog/ai_guard/evaluation/message'

RSpec.describe Datadog::AIGuard::Evaluation::Message do
  describe '.new' do
    it 'converts role to a symbol' do
      expect(described_class.new(role: "assistant").role).to eq(:assistant)
    end

    it 'raises an ArgumentError when nil role is passed' do
      expect { described_class.new(role: nil) }.to raise_error(
        ArgumentError, "Invalid role \"\", valid roles are: #{described_class::VALID_ROLES.join(", ")}"
      )
    end

    it 'raises an ArgumentError when invalid role is passed' do
      expect { described_class.new(role: :foo) }.to raise_error(
        ArgumentError, "Invalid role \"foo\", valid roles are: #{described_class::VALID_ROLES.join(", ")}"
      )
    end

    it 'raises an ArgumentError when :tool_call is not a ToolCall' do
      expect { described_class.new(role: :assistant, tool_call: "ls -la") }.to raise_error(
        ArgumentError, "Expected an instance of Datadog::AIGuard::Evaluation::ToolCall for :tool_call argument"
      )
    end
  end

  describe '#tool_call?' do
    it 'returns true when @tool_call attribute is set' do
      tool_call = Datadog::AIGuard::Evaluation::ToolCall.new("ls", id: "1", arguments: "-la")

      expect(described_class.new(role: :assistant, tool_call: tool_call)).to be_tool_call
    end

    it 'returns false when @tool_call attribute is not set' do
      expect(described_class.new(role: :assistant)).not_to be_tool_call
    end
  end

  describe '#tool_output?' do
    it 'returns true when @tool_call_id attribute is set' do
      expect(described_class.new(role: :assistant, tool_call_id: "1")).to be_tool_output
    end

    it 'returns false when @tool_call_id attribute is not set' do
      expect(described_class.new(role: :assistant)).not_to be_tool_output
    end
  end
end
