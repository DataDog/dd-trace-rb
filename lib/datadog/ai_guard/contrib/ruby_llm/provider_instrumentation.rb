# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      module RubyLLM
        # Protects messages sent to RubyLLM providers
        #
        # @api private
        module ProviderInstrumentation
          def complete(messages, **options, &block)
            adapter = MessageAdapter.new(messages)

            begin
              converted_messages = adapter.to_ai_guard
            rescue JSON::JSONError
              Metrics::Telemetry.report_error
              return super
            end

            evaluation = AIGuard.evaluate(*converted_messages)

            begin
              redacted_messages = adapter.apply_redactions(evaluation.messages)
            rescue JSON::JSONError
              Metrics::Telemetry.report_error
              return super
            end

            super(redacted_messages, **options, &block)
          end
        end
      end
    end
  end
end
