# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # module that gets prepended to RubyLLM::Chat
        module ChatInstrumentation
          class << self
            def evaluate(messages)
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

              puts '=' * 80
              puts ai_guard_messages.map(&:inspect)
              puts '=' * 80

              evaluation_result = AIGuard.evaluate(*ai_guard_messages, allow_raise: true)
            end
          end

          def complete(&block)
            evaluation_result = Datadog::AIGuard::Contrib::RubyLLM::ChatInstrumentation.evaluate(messages)

            super
          end

          def handle_tool_calls(response, &block)
            evaluation_result = Datadog::AIGuard::Contrib::RubyLLM::ChatInstrumentation.evaluate(messages)

            super
          end
        end
      end
    end
  end
end
