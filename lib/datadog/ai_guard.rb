# frozen_string_literal: true

require_relative "core/configuration"
require_relative "ai_guard/configuration"

module Datadog
  # A namespace for the AI Guard component.
  module AIGuard
    Core::Configuration::Settings.extend(Configuration::Settings)

    class << self
      def enabled?
        Datadog.configuration.ai_guard.enabled
      end

      def api_client
        Datadog.send(:components).ai_guard&.api_client
      end

      def logger
        Datadog.send(:components).ai_guard&.logger
      end

      def evaluate(*messages, allow_raise: false)
        if enabled?
          Evaluation.perform(messages, allow_raise: allow_raise)
        else
          Evaluation.perform_no_op
        end
      end

      def message(role:, content:)
        Evaluation::Message.new(role: role, content: content)
      end

      def assistant(tool_name:, id:, arguments:)
        Evaluation::Message.new(
          role: :assistant,
          tool_call: Evaluation::ToolCall.new(tool_name, id: id.to_s, arguments: arguments)
        )
      end

      def tool(tool_call_id:, content:)
        Evaluation::Message.new(role: :tool, tool_call_id: tool_call_id.to_s, content: content)
      end
    end
  end
end
