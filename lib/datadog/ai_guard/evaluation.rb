# frozen_string_literal: true

module Datadog
  module AIGuard
    # module that contains a function for performing AI Guard Evaluation request
    # and creating `ai_guard` span with required tags
    module Evaluation
      class << self
        def perform(messages, allow_raise: false)
          raise ArgumentError, "Messages must not be empty" if messages&.empty?

          Tracing.trace(Ext::SPAN_NAME) do |span, trace|
            if (last_message = messages.last)
              if last_message.tool_call
                span.set_tag(Ext::TARGET_TAG, "tool")
                span.set_tag(Ext::TOOL_NAME_TAG, last_message.tool_call.tool_name)
              elsif last_message.tool_call_id
                span.set_tag(Ext::TARGET_TAG, "tool")

                if (tool_call_message = messages.find { |m| m.tool_call&.id == last_message.tool_call_id })
                  span.set_tag(Ext::TOOL_NAME_TAG, tool_call_message.tool_call.tool_name) # steep:ignore
                end
              else
                span.set_tag(Ext::TARGET_TAG, "prompt")
              end
            end

            request = Request.new(messages)
            result = request.perform

            span.set_tag(Ext::ACTION_TAG, result.action)
            span.set_tag(Ext::REASON_TAG, result.reason)

            span.set_metastruct_tag(
              Ext::METASTRUCT_TAG,
              {messages: request.serialized_messages, attack_categories: result.tags}
            )

            if allow_raise && (result.deny? || result.abort?)
              span.set_tag(Ext::BLOCKED_TAG, true)
              raise Interrupt, result.reason
            end

            result
          end
        end

        def perform_no_op
          AIGuard.logger&.warn("AI Guard is disabled, messages were not evaluated")

          NoOpResult.new
        end
      end
    end
  end
end
