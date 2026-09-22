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
      expect { described_class.new(role: "") }.to raise_error(ArgumentError, "Role must be set to a non-empty value")
    end

    it "raises an ArgumentError when :tool_calls is not an array" do
      expect { described_class.new(role: :assistant, tool_calls: "ls -la") }.to raise_error(
        ArgumentError, "Tool calls must be an Array"
      )
    end

    it "raises an ArgumentError when :tool_calls contains something other than ToolCall instances" do
      expect { described_class.new(role: :assistant, tool_calls: ["ls -la"]) }.to raise_error(
        ArgumentError,
        "Tool calls must contain only Datadog::AIGuard::Evaluation::ToolCall instances"
      )
    end

    it "accepts an array of content parts" do
      parts = [
        Datadog::AIGuard::Evaluation::ContentPart::Text.new("Hello"),
        Datadog::AIGuard::Evaluation::ContentPart::ImageURL.new("https://example.com/img.png"),
      ]
      message = described_class.new(role: :user, content: parts)

      expect(message.content).to eq(parts)
    end

    it "accepts a block and yields a multi-modal content parts builder" do
      message = Datadog::AIGuard.message(role: :user) do |m|
        m.text("What's in this image?")
        m.image_url("https://example.com/img.png")
      end

      expect(message.role).to eq(:user)
      expect(message.content).to contain_exactly(
        an_instance_of(Datadog::AIGuard::Evaluation::ContentPart::Text),
        an_instance_of(Datadog::AIGuard::Evaluation::ContentPart::ImageURL),
      )
    end

    it "raises ArgumentError when both content and a block are provided" do
      expect {
        Datadog::AIGuard.message(role: :user, content: "Hello") { |m| m.text("World") }
      }.to raise_error(ArgumentError, "Cannot pass both content and a block")
    end
  end

  describe "#to_h" do
    context "when a message has content and tool calls" do
      let(:message) do
        described_class.new(
          role: :assistant,
          content: "Running tools",
          tool_calls: [
            Datadog::AIGuard::Evaluation::ToolCall.new("first", id: "call-1", arguments: '{"path":"~"}')
          ]
        )
      end

      it "serializes the content and tool calls" do
        expect(message.to_h).to eq(
          role: :assistant,
          content: "Running tools",
          tool_calls: [{id: "call-1", function: {name: "first", arguments: '{"path":"~"}'}}]
        )
      end
    end

    context "when a message has multiple tool calls" do
      let(:message) do
        described_class.new(
          role: :assistant,
          tool_calls: [
            Datadog::AIGuard::Evaluation::ToolCall.new("first", id: "call-1", arguments: "{}"),
            Datadog::AIGuard::Evaluation::ToolCall.new("second", id: "call-2", arguments: '{"value":2}')
          ]
        )
      end

      it "serializes every tool call in order" do
        expect(message.to_h).to eq(
          role: :assistant,
          tool_calls: [
            {id: "call-1", function: {name: "first", arguments: "{}"}},
            {id: "call-2", function: {name: "second", arguments: '{"value":2}'}}
          ]
        )
      end
    end
  end
end
