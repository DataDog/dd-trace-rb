# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Request builds the request body from an array of messages and processes the response
      class Request
        REQUEST_PATH = "/evaluate"

        attr_reader :serialized_messages

        def initialize(messages)
          @serialized_messages = serialize_messages(messages)
        end

        def perform
          # This should never happen, as we are only calling this method when AI Guard is enabled,
          # and this means the API Client was initialized properly.
          #
          # Please report this at https://github.com/datadog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug
          raise "AI Guard API Client not initialized" unless AIGuard.api_client

          raw_response = AIGuard.api_client.post(path: REQUEST_PATH, request_body: build_request_body) # steep:ignore

          Result.new(raw_response)
        end

        private

        def build_request_body
          {
            data: {
              attributes: {
                messages: @serialized_messages,
                meta: {
                  service: Datadog.configuration.service,
                  env: Datadog.configuration.env
                }
              }
            }
          }
        end

        def serialize_messages(messages)
          serialized_messages = []

          messages.each do |message|
            if serialized_messages.last&.key?(:tool_calls) && message.tool_call?
              # collapse subsequent tool calls
              serialized_messages.last.fetch(:tool_calls) << serialize_message(message).fetch(:tool_calls).first
            else
              serialized_messages << serialize_message(message)
            end

            break if serialized_messages.count == Datadog.configuration.ai_guard.max_messages_length
          end

          serialized_messages
        end

        def serialize_message(message)
          if message.tool_call?
            {
              role: message.role,
              tool_calls: [
                {
                  id: message.tool_call.id,
                  function: {
                    name: message.tool_call.tool_name,
                    arguments: message.tool_call.arguments
                  }
                }
              ]
            }
          elsif message.tool_output?
            {role: message.role, tool_call_id: message.tool_call_id, content: truncate_content(message.content)}
          else
            {role: message.role, content: truncate_content(message.content)}
          end
        end

        def truncate_content(content)
          return unless content

          content.byteslice(0, Datadog.configuration.ai_guard.max_content_size_bytes)
        end
      end
    end
  end
end
