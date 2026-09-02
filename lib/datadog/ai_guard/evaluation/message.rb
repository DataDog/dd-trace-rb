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

        def with_content(content)
          Message.new(role: role, content: content, tool_call: tool_call, tool_call_id: tool_call_id)
        end

        def with_tool_call(tool_call)
          Message.new(role: role, content: content, tool_call: tool_call, tool_call_id: tool_call_id)
        end

        def to_h
          if tool_call
            {role: role, tool_calls: [tool_call.to_h]}
          elsif content.is_a?(::Array)
            {role: role, content: content.map(&:to_h)}
          elsif tool_call_id
            {role: role, tool_call_id: tool_call_id, content: content}
          else
            {role: role, content: content}
          end
        end
      end
    end
  end
end
