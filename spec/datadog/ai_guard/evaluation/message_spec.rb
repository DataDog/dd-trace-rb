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
end
