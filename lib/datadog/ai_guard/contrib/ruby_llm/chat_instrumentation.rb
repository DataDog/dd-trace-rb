# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # module that gets prepended to RubyLLM::Chat
        module ChatInstrumentation
          def complete(&block)
            # FIXME: this gets called twice when there's a tool call
            result = super

            ai_guard_messages = messages.flat_map do |message|
              if message.tool_call?
                message.tool_calls.map do |tool_call_id, tool_call|
                  AIGuard.assistant(id: tool_call_id, tool_name: tool_call.name, arguments: tool_call.arguments.to_s)
                end
              elsif message.tool_result?
                AIGuard.tool(tool_call_id: message.tool_call_id, content: message.content)
              else
                AIGuard.message(role: message.role, content: message.content)
              end
            end
            evaluation_result = AIGuard.evaluate(*ai_guard_messages, allow_raise: false)

            result
          end
        end
      end
    end
  end
end
