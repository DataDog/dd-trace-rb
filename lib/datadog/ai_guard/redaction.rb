# frozen_string_literal: true

module Datadog
  module AIGuard
    module Redaction
      class << self
        def skip(messages)
          Redaction::Result.new(messages, applied: 0, failures: 0, performed: false)
        end

        def perform(messages, replacements:)
          applied = 0
          failures = 0
          redacted_messages = nil

          redaction_replacements = Replacements.new(replacements)
          failures += redaction_replacements.failures

          redaction_replacements.each do |path, replacement|
            index = path[0]
            message = redacted_messages ? redacted_messages[index] : messages[index]
            redacted_message = redact(message, path: path, replacement: replacement)

            next failures += 1 unless redacted_message

            redacted_messages ||= ::Array.new(messages)
            redacted_messages[index] = redacted_message

            applied += 1
          rescue
            failures += 1
          end

          Redaction::Result.new(
            redacted_messages || messages, applied: applied, failures: failures
          )
        end

        private

        def redact(message, path:, replacement:)
          return unless message.is_a?(Evaluation::Message)

          _, kind, index = path

          case kind
          when :content
            return if message.tool_call || !message.content.is_a?(::String)

            message.with_content(replacement)
          when :text
            content = message.content
            return if message.tool_call || !content.is_a?(::Array)

            part = content[index]
            return if !part.is_a?(Evaluation::ContentPart::Text) || !part.text.is_a?(::String)

            redacted_content = ::Array.new(content)
            redacted_content[index] = part.with_text(replacement)

            message.with_content(redacted_content)
          when :arguments
            tool_call = message.tool_call
            return if !tool_call || !tool_call.arguments.is_a?(::String)

            message.with_tool_call(tool_call.with_arguments(replacement))
          end
        end
      end
    end
  end
end
