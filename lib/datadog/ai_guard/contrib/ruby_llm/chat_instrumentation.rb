# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # module that gets prepended to RubyLLM::Chat
        module ChatInstrumentation
          class << self
            def evaluate!(messages)
              ai_guard_messages = messages.flat_map do |message|
                if message.tool_call?
                  message.tool_calls.map do |tool_call_id, tool_call|
                    AIGuard.assistant(id: tool_call_id, tool_name: tool_call.name, arguments: tool_call.arguments.to_s)
                  end
                elsif message.tool_result?
                  build_ai_guard_tool(message)
                else
                  build_ai_guard_message(message)
                end
              end

              AIGuard.evaluate(*ai_guard_messages)
            end

            private

            def build_ai_guard_message(message)
              content = message.content

              case content
              when ::RubyLLM::Content
                AIGuard.message(role: message.role) do |m|
                  m.text(content.text.to_s) if content.text

                  # Calling attachment.for_llm triggers lazy loading of file contents.
                  # The result is memoized, so providers won't re-read.
                  content.attachments.each do |attachment|
                    case attachment.type
                    when :image
                      m.image_url(attachment.for_llm)
                    when :text
                      m.text(attachment.for_llm)
                    end
                    # Skip :pdf, :audio, :video, :unknown — not supported by AIGuard
                  end
                end
              else
                AIGuard.message(role: message.role, content: content)
              end
            end

            def build_ai_guard_tool(message)
              content = message.content
              # Tools can return Content or Content::Raw objects (e.g. with attachments),
              # but AIGuard.tool expects a String. Extract text when content is a Content object.
              case content
              when ::RubyLLM::Content
                content = content.text.to_s
              end
              AIGuard.tool(tool_call_id: message.tool_call_id, content: content)
            end
          end

          def complete(&block)
            Datadog::AIGuard::Contrib::RubyLLM::ChatInstrumentation.evaluate!(messages)

            super
          end

          def handle_tool_calls(response, &block)
            Datadog::AIGuard::Contrib::RubyLLM::ChatInstrumentation.evaluate!(messages)

            super
          end
        end
      end
    end
  end
end
