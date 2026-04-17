# frozen_string_literal: true

module Datadog
  module AIGuard
    # module that contains a function for performing AI Guard Evaluation request
    # and creating `ai_guard` span with required tags
    module Evaluation
      class << self
        def perform(messages, allow_raise: true)
          raise ArgumentError, "Messages must not be empty" if messages&.empty?

          Tracing.trace(Ext::SPAN_NAME) do |span, trace|
            trace.keep!
            trace.set_tag(
              Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER,
              Tracing::Sampling::Ext::Decision::AI_GUARD
            )

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
              {
                messages: truncate_content(truncate_messages(request.serialized_messages)),
                attack_categories: result.tags,
                sds: result.sds_findings,
                tag_probs: result.tag_probabilities
              }
            )

            if allow_raise && (result.deny? || result.abort?) && result.blocking_enabled?
              span.set_tag(Ext::BLOCKED_TAG, true)
              raise AIGuardAbortError.new(action: result.action, reason: result.reason, tags: result.tags)
            end

            result
          end
        end

        def perform_no_op
          AIGuard.logger&.warn("AI Guard is disabled, messages were not evaluated")

          NoOpResult.new
        end

        private

        def truncate_messages(serialized_messages)
          max_length = Datadog.configuration.ai_guard.max_messages_length
          serialized_messages.first(max_length)
        end

        # Truncates content in serialized messages to stay within the configured byte limit.
        # For multi-modal messages, only text parts are truncated; image URLs are left intact.
        def truncate_content(serialized_messages)
          max_bytes = Datadog.configuration.ai_guard.max_content_size_bytes

          serialized_messages.map do |message| # steep:ignore
            next message unless message[:content]

            if message[:content].is_a?(::Array)
              serialized_content = message[:content].map do |part|
                if part[:text]
                  {**part, text: part[:text].to_s.byteslice(0, max_bytes)}
                else
                  part
                end
              end

              {**message, content: serialized_content}
            else
              {
                **message,
                content: message[:content].byteslice(0, max_bytes)
              }
            end
          end
        end
      end
    end
  end
end
