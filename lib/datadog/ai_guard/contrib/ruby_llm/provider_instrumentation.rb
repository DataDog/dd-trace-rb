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
            converted_messages = MessageConverter.convert(messages)

            unless converted_messages
              Metrics::Telemetry.report_error
              return super
            end

            evaluation = AIGuard.evaluate(*converted_messages)
            redacted_messages =
              if evaluation.messages.equal?(converted_messages)
                messages
              else
                MessageRedactor.redact(messages, with: evaluation.messages)
              end

            super(redacted_messages, **options, &block)
          end
        end
      end
    end
  end
end
