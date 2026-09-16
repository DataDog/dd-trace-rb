# frozen_string_literal: true

require "json"

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # Converts RubyLLM messages to AI Guard evaluation messages
        #
        # @api private
        module MessageConverter
          module_function

          def convert(messages)
            messages.flat_map do |message|
              if message.tool_call?
                build_tool_call(message)
              elsif message.tool_result?
                build_tool(message)
              else
                build_message(message)
              end
            end
          rescue JSON::JSONError
            nil
          end

          private_class_method def build_message(message)
            content = message.content

            case content
            when ::RubyLLM::Content
              AIGuard.message(role: message.role) do |builder|
                builder.text(content.text.to_s) if content.text

                # Calling attachment.for_llm triggers lazy loading of file contents
                # The result is memoized, so providers won't re-read
                content.attachments.each do |attachment|
                  case attachment.type
                  when :image
                    builder.image_url(attachment.for_llm)
                  when :text
                    builder.text(attachment.for_llm)
                  end
                  # Skip :pdf, :audio, :video, :unknown — not supported by AIGuard
                end
              end
            else
              AIGuard.message(role: message.role, content: content)
            end
          end

          private_class_method def build_tool(message)
            # Tools can return Content or Content::Raw objects (e.g. with attachments),
            # but AIGuard.tool expects a String. Extract text when content is a Content object
            content = message.content
            content = content.text.to_s if content.is_a?(::RubyLLM::Content)

            AIGuard.tool(tool_call_id: message.tool_call_id, content: content)
          end

          private_class_method def build_tool_call(message)
            message.tool_calls.map do |tool_call_id, tool_call|
              AIGuard.assistant(
                id: tool_call_id,
                tool_name: tool_call.name,
                arguments: JSON.generate(tool_call.arguments)
              )
            end
          end
        end
      end
    end
  end
end
