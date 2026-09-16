# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # Produces redacted copies of RubyLLM messages
        #
        # @api private
        module MessageRedactor
          module_function

          def redact(messages, with:)
            canonical_index = 0
            # @type var redacted_messages: Array[::RubyLLM::Message]?
            redacted_messages = nil

            messages.each_with_index do |message, index|
              canonical_message = with[canonical_index]
              canonical_index += message.tool_call? ? message.tool_calls.length : 1

              content = message.content
              canonical_content = canonical_message&.content

              next unless content.is_a?(String) && canonical_content.is_a?(String)
              next if canonical_content == content

              redacted_message = message.dup
              redacted_message.content = canonical_content

              redacted_messages ||= Array.new(messages) # Steep unable to assert non-nil after `||=`
              redacted_messages[index] = redacted_message # steep:ignore NoMethod
            end

            redacted_messages || messages
          end
        end
      end
    end
  end
end
