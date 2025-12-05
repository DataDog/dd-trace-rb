# frozen_string_literal: true

module Datadog
  module AIGuard
    # class that performs AI Guard Evaluation and creates `ai_guard` span
    class Evaluation
      class AIGuardAbortError < StandardError
        def initialize(reason)
          super()

          @reason = reason
        end

        def to_s
          "Request aborted. #{@reason}"
        end
      end

      class InvalidResponseError < StandardError
        def initialize(details)
          super()

          @details = details
        end

        def to_s
          "Invalid AI Guard API response. #{@details}"
        end
      end

      def initialize(messages)
        @messages = messages
      end

      def perform(allow_raise: false)
        Tracing.trace(Ext::SPAN_NAME) do |span, trace|
          if (last_message = @messages.last)
            if last_message.role == :tool
              span.set_tag(Ext::TARGET_TAG, 'tool')
              span.set_tag(Ext::TOOL_NAME_TAG, last_message.tool_call.tool_name)
            else
              span.set_tag(Ext::TARGET_TAG, 'prompt')
            end
          end

          request = Request.new(@messages)
          response = request.perform

          span.set_tag(Ext::ACTION_TAG, response.action)
          span.set_tag(Ext::REASON_TAG, response.reason) unless response.allow?

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
