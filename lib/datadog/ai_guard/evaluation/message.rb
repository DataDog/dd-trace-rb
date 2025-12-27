# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Message class for AI Guard
      class Message
        attr_reader :role, :content, :tool_call, :tool_call_id

        def initialize(role:, content: nil, tool_call: nil, tool_call_id: nil)
          raise ArgumentError, "Role must be set to a non-empty value" if role.to_s.empty?

          @role = role.to_sym
          @content = content
          @tool_call = tool_call
          @tool_call_id = tool_call_id

          if @tool_call && !@tool_call.is_a?(ToolCall)
            raise ArgumentError, "Expected an instance of #{ToolCall.name} for :tool_call argument"
          end
        end
      end
    end
  end
end
