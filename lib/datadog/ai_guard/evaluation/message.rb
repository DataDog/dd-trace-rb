# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Represents a message submitted for evaluation
      class Message
        attr_reader :role, :content, :tool_calls, :tool_call_id

        def initialize(role:, content: nil, tool_calls: [], tool_call_id: nil)
          raise ArgumentError, "Role must be set to a non-empty value" if role.to_s.empty?
          raise ArgumentError, "Tool calls must be an Array" unless tool_calls.is_a?(::Array)

          if tool_calls.any? { |tool_call| !tool_call.is_a?(ToolCall) }
            raise ArgumentError, "Tool calls must contain only #{ToolCall.name} instances"
          end

          @role = role.to_sym
          @content = content
          @tool_calls = tool_calls
          @tool_call_id = tool_call_id
        end

        def with_content(content)
          Message.new(role: role, content: content, tool_calls: tool_calls, tool_call_id: tool_call_id)
        end

        def with_tool_calls(tool_calls)
          Message.new(role: role, content: content, tool_calls: tool_calls, tool_call_id: tool_call_id)
        end

        def to_h
          serialized = {
            role: role,
            content: content.is_a?(::Array) ? content.map(&:to_h) : content,
            tool_call_id: tool_call_id
          }

          serialized[:tool_calls] = tool_calls.map(&:to_h) unless tool_calls.empty?
          serialized.compact!

          serialized
        end
      end
    end
  end
end
