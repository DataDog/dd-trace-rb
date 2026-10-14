# frozen_string_literal: true

module Datadog
  module AIGuard
    # Sensitive data redaction for evaluation messages
    #
    # @api private
    module Redaction
      class << self
        def skip(messages)
          Redaction::Result.new(messages, applied_count: 0, failures_count: 0, performed: false)
        end

        def perform(messages, replacements:)
          redaction_replacements = Replacements.new(replacements)
          failures_count = redaction_replacements.failures_count

          if redaction_replacements.empty?
            return Redaction::Result.new(messages, applied_count: 0, failures_count: failures_count)
          end

          applied_count = 0
          redacted_messages = messages.dup

          redaction_replacements.each do |path, replacement|
            index = path[0]
            redacted_message = redact(redacted_messages[index], path: path, replacement: replacement)

            next failures_count += 1 unless redacted_message

            redacted_messages[index] = redacted_message
            applied_count += 1
          rescue
            failures_count += 1
          end

          Redaction::Result.new(
            redacted_messages, applied_count: applied_count, failures_count: failures_count
          )
        end

        private

        def redact(message, path:, replacement:)
          return unless message.is_a?(Evaluation::Message)

          _, kind, index = path

          case kind
          when :content
            return unless message.content.is_a?(::String)

            message.copy(content: replacement)
          when :text
            # @type var index: Integer
            content = message.content
            return unless content.is_a?(::Array)

            part = content[index]
            return if !part.is_a?(Evaluation::ContentPart::Text) || !part.text.is_a?(::String)

            redacted_content = ::Array.new(content)
            redacted_content[index] = part.copy(text: replacement)

            message.copy(content: redacted_content)
          when :arguments
            # @type var index: Integer
            tool_call = message.tool_calls[index]
            return unless tool_call && tool_call.arguments.is_a?(::String)

            redacted_tool_calls = ::Array.new(message.tool_calls)
            redacted_tool_calls[index] = tool_call.copy(arguments: replacement)

            message.copy(tool_calls: redacted_tool_calls)
          end
        end
      end
    end
  end
end
