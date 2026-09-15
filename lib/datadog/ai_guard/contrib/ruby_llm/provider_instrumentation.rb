# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # Protects messages sent to RubyLLM providers
        #
        # @api private
        module ProviderInstrumentation
          def complete(messages, **options, &block)
            super(redact(messages), **options, &block)
          end

          private

          def redact(messages)
            evaluated_messages = ChatInstrumentation.evaluate!(messages).messages
            evaluated_index = 0
            # @type var redacted_messages: Array[::RubyLLM::Message]?
            redacted_messages = nil

            messages.each_with_index do |message, index|
              evaluated_message = evaluated_messages[evaluated_index]
              evaluated_index += message.tool_call? ? message.tool_calls.length : 1

              content = message.content
              redacted_content = evaluated_message&.content
              next unless content.is_a?(String) && redacted_content.is_a?(String)
              next if redacted_content == content

              redacted_messages ||= Array.new(messages) # Steep unable to assert non-nil after `||=`
              redacted_message = message.dup
              redacted_message.content = redacted_content
              redacted_messages[index] = redacted_message # steep:ignore NoMethod
            end

            redacted_messages || messages
          end
        end
      end
    end
  end
end
