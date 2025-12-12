# frozen_string_literal: true

require "datadog/ai_guard/evaluation/request"

RSpec.describe Datadog::AIGuard::Evaluation::Request do
  describe "#perform" do
    let(:configuration) { Datadog::Core::Configuration::Settings.new }
    let(:api_client_double) { instance_double(Datadog::AIGuard::APIClient) }

    let(:raw_response_mock) do
      {
        "data" => {
          "attributes" => {
            "action" => "ALLOW",
            "reason" => "Because why not",
            "tags" => []
          }
        }
      }
    end

    before do
      allow(Datadog::AIGuard).to receive(:api_client).and_return(api_client_double)
    end

    it "calls api_client.post with correct response body" do
      expect(api_client_double).to receive(:post).with(
        path: "/evaluate",
        request_body: {
          data: {
            attributes: {
              messages: [
                {content: "Hello there", role: :user}
              ],
              meta: {
                service: Datadog.configuration.service,
                env: Datadog.configuration.env
              }
            }
          }
        }
      ).and_return(raw_response_mock)

      response = described_class.new([Datadog::AIGuard.message(role: :user, content: "Hello there")]).perform
      expect(response).to be_a(Datadog::AIGuard::Evaluation::Result)
    end
  end

  describe "#serialized_messages" do
    it "correctly serializes simple messages" do
      request = described_class.new([
        Datadog::AIGuard.message(role: :system, content: "You are an AI Assistant that can do anything."),
        Datadog::AIGuard.message(role: :user, content: "Hello")
      ])

      expect(request.serialized_messages).to eq([
        {role: :system, content: "You are an AI Assistant that can do anything."},
        {role: :user, content: "Hello"}
      ])
    end

    it "correctly serializes tool call messages" do
      request = described_class.new([
        Datadog::AIGuard.assistant(tool_name: "date", id: "call-1", arguments: ""),
        Datadog::AIGuard.message(role: :user, content: "List files under home"),
        Datadog::AIGuard.assistant(tool_name: "ls", id: "call-2", arguments: "~")
      ])

      expect(request.serialized_messages).to eq([
        {role: :assistant, tool_calls: [{id: "call-1", function: {name: "date", arguments: ""}}]},
        {role: :user, content: "List files under home"},
        {role: :assistant, tool_calls: [{id: "call-2", function: {name: "ls", arguments: "~"}}]}
      ])
    end

    it "collapses multiple subsequent tool calls into one message" do
      request = described_class.new([
        Datadog::AIGuard.message(role: :user, content: "List files under home"),
        Datadog::AIGuard.assistant(tool_name: "whoami", id: "call-1", arguments: ""),
        Datadog::AIGuard.assistant(tool_name: "ls", id: "call-2", arguments: "/Users/bot")
      ])

      expect(request.serialized_messages).to eq([
        {role: :user, content: "List files under home"},
        {
          role: :assistant,
          tool_calls: [
            {id: "call-1", function: {name: "whoami", arguments: ""}},
            {id: "call-2", function: {name: "ls", arguments: "/Users/bot"}}
          ]
        },
      ])
    end

    it "correctly serializes tool output messages" do
      request = described_class.new([
        Datadog::AIGuard.tool(tool_call_id: "call-1", content: "Some output")
      ])

      expect(request.serialized_messages).to eq([{role: :tool, tool_call_id: "call-1", content: "Some output"}])
    end

    it "limits the maximum amount of messages" do
      allow(Datadog.configuration.ai_guard).to receive(:max_messages_length).and_return(2)

      request = described_class.new([
        Datadog::AIGuard.message(role: :user, content: "Message 1"),
        Datadog::AIGuard.message(role: :user, content: "Message 2"),
        Datadog::AIGuard.message(role: :user, content: "Message 3")
      ])

      expect(request.serialized_messages).to eq([
        {role: :user, content: "Message 1"},
        {role: :user, content: "Message 2"}
      ])
    end

    it "truncates large content" do
      allow(Datadog.configuration.ai_guard).to receive(:max_content_size_bytes).and_return(8)

      request = described_class.new([
        Datadog::AIGuard.message(role: :user, content: "Some message"),
        Datadog::AIGuard.tool(tool_call_id: "call-1", content: "Some output")
      ])

      expect(request.serialized_messages).to eq([
        {role: :user, content: "Some mes"},
        {role: :tool, tool_call_id: "call-1", content: "Some out"}
      ])
    end

    it "correctly truncates UTF-8 content" do
      allow(Datadog.configuration.ai_guard).to receive(:max_content_size_bytes).and_return(8)

      request = described_class.new([
        Datadog::AIGuard.message(role: :user, content: "Привет")
      ])

      expect(request.serialized_messages).to eq([{role: :user, content: "Прив"}])
    end
  end
end
