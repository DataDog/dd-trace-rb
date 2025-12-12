# frozen_string_literal: true

module Datadog
  module AIGuard
    # module that contains a function for performing AI Guard Evaluation request
    # and creating `ai_guard` span with required tags
    module Evaluation
      # This error is raised when user passes `allow_raise: true` to Evaluation.perform.
      # It is intended to be rescued by the user.
      class AIGuardAbortError < StandardError
        attr_reader :reason

        def initialize(reason)
          super()

          @reason = reason
        end

        def to_s
          "Request aborted. #{@reason}"
        end
      end

      class UnexpectedResponseError < StandardError
        def initialize(details)
          super()

          @details = details
        end

        def to_s
          "Invalid AI Guard API response. #{@details}"
        end
      end

      class << self
        def perform(messages, allow_raise: false)
          raise ArgumentError, "Messages must not be empty" if messages&.empty?

          Tracing.trace(Ext::SPAN_NAME) do |span, trace|
            if (last_message = messages.last)
              if last_message.tool_call?
                span.set_tag(Ext::TARGET_TAG, 'tool')
                span.set_tag(Ext::TOOL_NAME_TAG, last_message.tool_call.tool_name)
              elsif last_message.tool_output?
                span.set_tag(Ext::TARGET_TAG, 'tool')

                if (tool_call_message = messages.find { |m| m.tool_call&.id == last_message.tool_call_id })
                  span.set_tag(Ext::TOOL_NAME_TAG, tool_call_message.tool_call.tool_name)
                end
              else
                span.set_tag(Ext::TARGET_TAG, 'prompt')
              end
            end

            request = Request.new(messages)
            response = request.perform

            span.set_tag(Ext::ACTION_TAG, response.action)
            span.set_tag(Ext::REASON_TAG, response.reason)

            span.set_metastruct_tag(
              Ext::METASTRUCT_TAG,
              {messages: request.serialized_messages, attack_categories: response.tags}
            )

            if allow_raise && (response.deny? || response.abort?)
              span.set_tag(Ext::BLOCKED_TAG, true)
              raise Evaluation::AIGuardAbortError, response.reason
            end

            response
          end
        end
      end
    end
  end
end
