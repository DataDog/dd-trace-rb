# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # module that gets prepended to RubyLLM::Chat
        module ChatInstrumentation
          def handle_tool_calls(response, &block)
            converted_messages = MessageConverter.convert(messages)

            unless converted_messages
              Metrics::Telemetry.report_error
              return super
            end

            AIGuard.evaluate(*converted_messages)

            super
          end
        end
      end
    end
  end
end
