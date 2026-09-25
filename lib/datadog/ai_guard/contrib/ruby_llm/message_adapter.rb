# frozen_string_literal: true

require_relative "redaction_change_set"

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # RubyLLM messages paired with their AI Guard representation
        #
        # @api private
        class MessageAdapter
          def initialize(messages)
            @ruby_llm_messages = messages
          end

          def to_ai_guard
            @ai_guard_messages ||= @ruby_llm_messages.map { |message| build_ai_guard_message(message) }
          end

          def apply_redactions(redacted_messages)
            ai_guard_messages = to_ai_guard
            return @ruby_llm_messages if redacted_messages == ai_guard_messages

            @ruby_llm_messages.each_with_index.map do |message, index|
              original_message = ai_guard_messages[index]
              redacted_message = redacted_messages[index]
              next message if redacted_message == original_message

              RedactionChangeSet.new(original_message, redacted_message).apply_to(message)
            end
          end

          private

          def build_ai_guard_message(message)
            # NOTE: Hash block arguments are misinterpreted by Steep after `nil.to_h`
            # steep:ignore:start
            tool_calls = message.tool_calls.to_h.map do |id, tool_call|
              AIGuard.tool_call(name: tool_call.name, id: id, arguments: tool_call.arguments)
            end
            # steep:ignore:end

            if message.attachments.empty?
              return AIGuard.message(
                role: message.role, content: message.content, tool_calls: tool_calls, tool_call_id: message.tool_call_id
              )
            end

            AIGuard.message(role: message.role, tool_calls: tool_calls, tool_call_id: message.tool_call_id) do |builder|
              builder.text(message.content) if message.content && !message.content.empty?

              message.attachments.each do |attachment|
                next if attachment.provider_file?

                case attachment.type
                when :text
                  builder.text(attachment.content)
                when :image
                  # NOTE: Local images are Base64-encoded here by `#for_llm`
                  #       and again when RubyLLM builds the provider request
                  url = attachment.url? ? attachment.source.to_s : attachment.for_llm
                  builder.image_url(url)
                end
              end
            end
          end
        end
      end
    end
  end
end
