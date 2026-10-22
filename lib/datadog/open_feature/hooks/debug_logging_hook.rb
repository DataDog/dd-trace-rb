# frozen_string_literal: true

require_relative "../ext"

module Datadog
  module OpenFeature
    module Hooks
      # Logs each SDK-final evaluation outcome for onboarding diagnostics.
      #
      # Logs raw flag values, default values, targeting keys, context attributes, and
      # error messages, so it is only registered while debug logging is enabled.
      class DebugLoggingHook
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        def self.available?
          !!defined?(::OpenFeature::SDK::Hooks::Hook)
        end

        def initialize(logger)
          @logger = logger
        end

        def finally(hook_context:, evaluation_details:, **_opts)
          return unless @logger.debug?

          evaluation_context = hook_context.evaluation_context
          @logger.debug(
            "Feature Flags: evaluated #{hook_context.flag_key.inspect} (" \
              "type=#{hook_context.flag_value_type}, " \
              "default=#{hook_context.default_value.inspect}, " \
              "value=#{evaluation_details.value.inspect}, " \
              "variant=#{evaluation_details.variant.inspect}, " \
              "reason=#{evaluation_details.reason.inspect}, " \
              "allocation=#{extract_allocation_key(evaluation_details).inspect}, " \
              "error_code=#{evaluation_details.error_code.inspect}, " \
              "error_message=#{evaluation_details.error_message.inspect}, " \
              "targeting_key=#{evaluation_context&.targeting_key.inspect}, " \
              "attributes=#{attributes(evaluation_context).inspect}, " \
              "flag_metadata=#{evaluation_details.flag_metadata.inspect})"
          )
        rescue
          nil
        end

        private

        def extract_allocation_key(evaluation_details)
          metadata = evaluation_details.flag_metadata
          return unless metadata.is_a?(Hash)

          metadata[Ext::METADATA_ALLOCATION_KEY]
        end

        def attributes(evaluation_context)
          return {} unless evaluation_context

          evaluation_context.fields.reject { |key, _value| key == ::OpenFeature::SDK::EvaluationContext::TARGETING_KEY }
        end
      end
    end
  end
end
