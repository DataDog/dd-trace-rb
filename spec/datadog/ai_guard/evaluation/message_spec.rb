# frozen_string_literal: true

require "datadog/ai_guard/evaluation/message"

RSpec.describe Datadog::AIGuard::Evaluation::Message do
  describe ".new" do
    it "converts role to a symbol" do
      expect(described_class.new(role: "assistant").role).to eq(:assistant)
    end

    it "raises an ArgumentError when nil role is passed" do
      expect { described_class.new(role: nil) }.to raise_error(ArgumentError, "Role must be set to a non-empty value")
    end

    it "raises an ArgumentError when an empty role is passed" do
      expect { described_class.new(role: '') }.to raise_error(ArgumentError, "Role must be set to a non-empty value")
    end

    it "raises an ArgumentError when :tool_call is not a ToolCall" do
      expect { described_class.new(role: :assistant, tool_call: "ls -la") }.to raise_error(
        ArgumentError, "Expected an instance of Datadog::AIGuard::Evaluation::ToolCall for :tool_call argument"
      )
    end
  end
end
