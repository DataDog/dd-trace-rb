# frozen_string_literal: true

require_relative "../ext"

module Datadog
  module OpenFeature
    module Hooks
      # Logs each SDK-final evaluation outcome for onboarding diagnostics.
      #
      # Flag values, targeting keys, context attributes, and error messages are
      # never logged: any of them may carry end-user data.
      class DebugLoggingHook
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        def self.available?
          !!defined?(::OpenFeature::SDK::Hooks::Hook)
        end

        def initialize(logger)
          @logger = logger
        end

        def finally(hook_context:, evaluation_details:, **_opts)
          @logger.debug do
            "Feature Flags: evaluated #{hook_context.flag_key.inspect} (" \
              "reason=#{evaluation_details.reason.inspect}, " \
              "variant=#{evaluation_details.variant.inspect}, " \
              "allocation=#{extract_allocation_key(evaluation_details).inspect}, " \
              "error_code=#{evaluation_details.error_code.inspect}, " \
              "targeting_key=#{targeting_key_presence(hook_context.evaluation_context)})"
          end
        end

        private

        def extract_allocation_key(evaluation_details)
          metadata = evaluation_details.flag_metadata
          return unless metadata.is_a?(Hash)

          metadata[Ext::METADATA_ALLOCATION_KEY]
        end

        def targeting_key_presence(evaluation_context)
          targeting_key = evaluation_context&.targeting_key
          targeting_key.to_s.empty? ? "absent" : "present"
        end
      end
    end
  end
end
