# frozen_string_literal: true

require_relative 'core/configuration'
require_relative 'ai_guard/configuration'

module Datadog
  # A namespace for the AI Guard component.
  module AIGuard
    Core::Configuration::Settings.extend(Configuration::Settings)

    module_function

    def enabled?
      Datadog.configuration.ai_guard.enabled
    end

    def api_client
      Datadog.send(:components).ai_guard&.api_client
    end

    def evaluate(*messages, allow_raise: false)
      Evaluation.new(messages).perform(allow_raise: allow_raise)
    end

    def message(role:, content:)
      Evaluation::Message.new(role: role, content: content)
    end

    def tool_call(tool_name, id:, arguments:)
      Evaluation::Message.new(
        role: :assistant,
        tool_call: Evaluation::ToolCall.new(tool_name, id: id, arguments: arguments)
      )
    end

    def tool_output(tool_call_id:, content:)
      Evaluation::Message.new(role: :tool, tool_call_id: tool_call_id, content: content)
    end
  end
end
