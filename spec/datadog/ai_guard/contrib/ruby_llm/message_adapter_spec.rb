# frozen_string_literal: true

require "ruby_llm"
require "datadog/ai_guard"
require "datadog/ai_guard/contrib/ruby_llm/message_adapter"

require "spec_helper"

RSpec.describe Datadog::AIGuard::Contrib::RubyLLM::MessageAdapter do
  describe "#to_ai_guard" do
    context "when a message contains content and multiple tool calls" do
      let(:adapter) { described_class.new([message]) }
      let(:message) do
        RubyLLM::Message.new(
          role: :assistant,
          content: "Running commands",
          tool_calls: {
            "call_1" => RubyLLM::ToolCall.new(id: "call_1", name: "shell", arguments: {"command" => "ls /"}),
            "call_2" => RubyLLM::ToolCall.new(id: "call_2", name: "search", arguments: {"query" => "secret"})
          }
        )
      end

      it "preserves the message and serializes every tool call" do
        converted_message = adapter.to_ai_guard[0]

        aggregate_failures("converted message") do
          expect(converted_message.role).to eq(:assistant)
          expect(converted_message.content).to eq("Running commands")
          expect(converted_message.tool_calls[0].id).to eq("call_1")
          expect(converted_message.tool_calls[0].arguments).to eq('{"command":"ls /"}')
          expect(converted_message.tool_calls[1].id).to eq("call_2")
          expect(converted_message.tool_calls[1].arguments).to eq('{"query":"secret"}')
        end
      end
    end

    context "when a message contains supported attachments" do
      let(:adapter) { described_class.new([message]) }
      let(:message) do
        RubyLLM::Message.new(
          role: :user,
          content: "Inspect these files",
          attachments: [
            RubyLLM::Attachment.new(StringIO.new("Account 123"), filename: "notes.txt"),
            RubyLLM::Attachment.new(StringIO.new("\x89PNG\r\n\x1A\n".b), filename: "photo.png")
          ]
        )
      end

      it "converts message text, text attachments, and image attachments into content parts" do
        content = adapter.to_ai_guard[0].content

        aggregate_failures("converted content") do
          expect(content[0].to_h).to eq(type: "text", text: "Inspect these files")
          expect(content[1].to_h).to eq(type: "text", text: "Account 123")
          expect(content[2].to_h.fetch(:type)).to eq("image_url")
          expect(content[2].to_h.dig(:image_url, :url)).to start_with("data:image/png;base64,")
        end
      end
    end

    context "when tool-call arguments cannot be encoded as JSON" do
      let(:adapter) { described_class.new([message]) }
      let(:message) do
        recursive_arguments = {}
        recursive_arguments["recursive"] = recursive_arguments

        RubyLLM::Message.new(
          role: :assistant,
          content: "Running the command",
          tool_calls: {
            "call_1" => RubyLLM::ToolCall.new(id: "call_1", name: "shell", arguments: recursive_arguments)
          }
        )
      end

      it { expect { adapter.to_ai_guard }.to raise_error(JSON::NestingError) }
    end
  end

  describe "#apply_redactions" do
    context "when messages were not redacted" do
      let(:adapter) { described_class.new(messages) }
      let(:messages) { [RubyLLM::Message.new(role: :user, content: "Hello")] }

      it { expect(adapter.apply_redactions(adapter.to_ai_guard)).to be(messages) }
    end

    context "when string content was redacted" do
      let(:adapter) { described_class.new([message]) }
      let(:message) do
        RubyLLM::Message.new(
          role: :user,
          content: "Account 123",
          raw_content: [{"type" => "input_text", "text" => "Account 123"}]
        )
      end

      it "copies the message and clears provider-shaped content" do
        ai_guard_message = adapter.to_ai_guard[0]
        rewritten_message = adapter.apply_redactions([ai_guard_message.with_content("Account <REDACTED>")])[0]

        aggregate_failures("rewritten message") do
          expect(rewritten_message.content).to eq("Account <REDACTED>")
          expect(rewritten_message.raw_content).to be_nil
          expect(message.content).to eq("Account 123")
          expect(rewritten_message).not_to be(message)
        end
      end
    end

    context "when one of multiple tool calls was redacted" do
      let(:adapter) { described_class.new([message]) }
      let(:message) do
        RubyLLM::Message.new(
          role: :assistant,
          content: "Running commands",
          tool_calls: {"call_1" => first_tool_call, "call_2" => second_tool_call}
        )
      end
      let(:first_tool_call) do
        RubyLLM::ToolCall.new(id: "call_1", name: "shell", arguments: {"command" => "pwd"})
      end
      let(:second_tool_call) do
        RubyLLM::ToolCall.new(id: "call_2", name: "shell", arguments: {"command" => "ls /"})
      end

      it "copies only the changed message and tool call" do
        ai_guard_message = adapter.to_ai_guard[0]
        redacted_tool_calls = Array.new(ai_guard_message.tool_calls)
        redacted_tool_calls[1] = redacted_tool_calls[1].with_arguments('{"command":"<REDACTED>"}')
        rewritten_message = adapter.apply_redactions([ai_guard_message.with_tool_calls(redacted_tool_calls)])[0]

        aggregate_failures("rewritten tool calls") do
          expect(rewritten_message.tool_calls.fetch("call_1")).to be(first_tool_call)
          expect(rewritten_message.tool_calls.fetch("call_2").arguments).to eq("command" => "<REDACTED>")
          expect(second_tool_call.arguments).to eq("command" => "ls /")
        end
      end
    end

    context "when a text attachment was redacted" do
      let(:adapter) { described_class.new([message]) }
      let(:message) do
        RubyLLM::Message.new(
          role: :user,
          content: "Read this file",
          attachments: [attachment]
        )
      end
      let(:attachment) { RubyLLM::Attachment.new(StringIO.new("Account 123"), filename: "notes.txt") }

      it "copies the attachment and preserves the original" do
        ai_guard_message = adapter.to_ai_guard[0]
        redacted_content = Array.new(ai_guard_message.content)
        redacted_content[1] = redacted_content[1].with_text("Account <REDACTED>")
        rewritten_message = adapter.apply_redactions([ai_guard_message.with_content(redacted_content)])[0]

        aggregate_failures("rewritten attachment") do
          expect(rewritten_message.attachments[0].content).to eq("Account <REDACTED>")
          expect(rewritten_message.attachments[0].filename).to eq("notes.txt")
          expect(attachment.content).to eq("Account 123")
        end
      end
    end

    context "when redacted tool-call arguments are invalid JSON" do
      let(:adapter) { described_class.new([message]) }
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

      it "fails conversion without changing the original message" do
        ai_guard_message = adapter.to_ai_guard[0]
        redacted_tool_calls = [ai_guard_message.tool_calls[0].with_arguments("invalid")]

        expect do
          adapter.apply_redactions([ai_guard_message.with_tool_calls(redacted_tool_calls)])
        end.to raise_error(JSON::ParserError)
        expect(tool_call.arguments).to eq("command" => "ls /")
      end
    end

    context "when a later tool-call redaction contains invalid JSON" do
      let(:adapter) { described_class.new([user_message, tool_call_message]) }
      let(:user_message) { RubyLLM::Message.new(role: :user, content: "Account 123") }
      let(:tool_call_message) do
        RubyLLM::Message.new(
          role: :assistant,
          content: "Running the command",
          tool_calls: {"call_1" => tool_call}
        )
      end
      let(:tool_call) do
        RubyLLM::ToolCall.new(id: "call_1", name: "shell", arguments: {"command" => "ls /"})
      end
      let(:redacted_messages) do
        ai_guard_messages = adapter.to_ai_guard
        redacted_tool_calls = [ai_guard_messages[1].tool_calls[0].with_arguments("invalid")]

        [
          ai_guard_messages[0].with_content("Account <REDACTED>"),
          ai_guard_messages[1].with_tool_calls(redacted_tool_calls)
        ]
      end

      it "raises without changing any original message" do
        expect { adapter.apply_redactions(redacted_messages) }.to raise_error(JSON::ParserError)

        aggregate_failures("original messages") do
          expect(user_message.content).to eq("Account 123")
          expect(tool_call.arguments).to eq("command" => "ls /")
        end
      end
    end
  end
end
