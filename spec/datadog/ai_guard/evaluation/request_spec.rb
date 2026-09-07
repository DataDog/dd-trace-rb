# frozen_string_literal: true

require "datadog/ai_guard/evaluation/request"

RSpec.describe Datadog::AIGuard::Evaluation::Request do
  describe "#body" do
    subject(:body) { described_class.new(messages).body }

    let(:messages) do
      [
        Datadog::AIGuard::Evaluation::Message.new(role: :user, content: "Hello there"),
      ]
    end

    it "builds the evaluation request body" do
      expect(body).to eq(
        data: {
          attributes: {
            messages: [
              {content: "Hello there", role: :user},
            ],
            meta: {
              service: Datadog.configuration.service,
              env: Datadog.configuration.env,
            },
          },
        }
      )
    end

    context "when messages contain tool calls" do
      let(:messages) do
        [
          Datadog::AIGuard.assistant(tool_name: "date", id: "call-1", arguments: ""),
          Datadog::AIGuard.message(role: :user, content: "List files under home"),
          Datadog::AIGuard.assistant(tool_name: "ls", id: "call-2", arguments: "~"),
        ]
      end

      it "serializes the tool calls" do
        expect(body.dig(:data, :attributes, :messages)).to eq([
          {role: :assistant, tool_calls: [{id: "call-1", function: {name: "date", arguments: ""}}]},
          {role: :user, content: "List files under home"},
          {role: :assistant, tool_calls: [{id: "call-2", function: {name: "ls", arguments: "~"}}]},
        ])
      end
    end

    context "when messages contain tool output" do
      let(:messages) do
        [
          Datadog::AIGuard.tool(tool_call_id: "call-1", content: "Some output"),
        ]
      end

      it "serializes the tool output" do
        expect(body.dig(:data, :attributes, :messages)).to eq(
          [{role: :tool, tool_call_id: "call-1", content: "Some output"}]
        )
      end
    end

    context "when messages contain multi-modal content" do
      let(:messages) do
        [
          Datadog::AIGuard.message(role: :user) do |message|
            message.text("What's in this image?")
            message.image_url("https://example.com/img.png")
          end,
        ]
      end

      it "serializes the content parts" do
        expect(body.dig(:data, :attributes, :messages)).to eq([
          {
            role: :user,
            content: [
              {type: "text", text: "What's in this image?"},
              {type: "image_url", image_url: {url: "https://example.com/img.png"}},
            ],
          },
        ])
      end
    end

    context "when messages exceed the meta-struct message limit" do
      before { allow(Datadog.configuration.ai_guard).to receive(:max_messages_length).and_return(2) }

      let(:messages) do
        [
          Datadog::AIGuard.message(role: :user, content: "Message 1"),
          Datadog::AIGuard.message(role: :user, content: "Message 2"),
          Datadog::AIGuard.message(role: :user, content: "Message 3"),
        ]
      end

      it "serializes every message" do
        expect(body.dig(:data, :attributes, :messages)).to eq([
          {role: :user, content: "Message 1"},
          {role: :user, content: "Message 2"},
          {role: :user, content: "Message 3"},
        ])
      end
    end
  end
end
