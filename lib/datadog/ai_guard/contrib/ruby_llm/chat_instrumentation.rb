# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # Protects tool calls before RubyLLM executes them locally
        #
        # @api private
        module ChatInstrumentation
          def preprocessed_messages(list = messages)
            adapter = MessageAdapter.new(list)

            begin
              converted_messages = adapter.to_ai_guard
            rescue JSON::JSONError
              Metrics::Telemetry.report_error
              return super(list)
            end

            evaluation = AIGuard.evaluate(*converted_messages)

            begin
              redacted_messages = adapter.apply_redactions(evaluation.messages)
            rescue JSON::JSONError
              Metrics::Telemetry.report_error
              return super(list)
            end

            super(redacted_messages)
          end

          def execute_pending_tool_calls(response)
            response_index = messages.index { |message| message == response }
            return super unless response_index

            adapter = MessageAdapter.new(messages)
            begin
              converted_messages = adapter.to_ai_guard
            rescue JSON::JSONError
              Metrics::Telemetry.report_error
              return super(response)
            end

            evaluation = AIGuard.evaluate(*converted_messages)
            begin
              redacted_messages = adapter.apply_redactions(evaluation.messages)
            rescue JSON::JSONError
              Metrics::Telemetry.report_error
              return super
            end

            super(redacted_messages[response_index])
          end
        end
      end
    end
  end
end
