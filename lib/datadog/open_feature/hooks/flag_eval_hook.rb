# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Hooks
      # Records flag evaluation metrics via OpenTelemetry hook
      #
      # Compatible with OpenFeature SDK >= 0.5.0 which provides the Hooks::Hook module,
      # but also works with older versions since the SDK uses respond_to?(:finally)
      # to detect hook capabilities.
      class FlagEvalHook
        # Include the Hook module if available (SDK >= 0.5.0) for interface documentation
        # and default implementations of other hook methods (before, after, error)
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        # Returns true if the OpenFeature SDK supports hooks (>= 0.5.0)
        def self.available?
          defined?(::OpenFeature::SDK::Hooks::Hook) ? true : false
        end

        def initialize(metrics)
          @metrics = metrics
        end

        def finally(hook_context:, evaluation_details:, **_opts)
          metrics = @metrics
          return unless metrics

          metrics.record(
            hook_context.flag_key,
            variant: evaluation_details.variant,
            reason: evaluation_details.reason,
            error_code: evaluation_details.error_code,
            allocation_key: extract_allocation_key(evaluation_details),
          )
        end

        private

        def extract_allocation_key(evaluation_details)
          metadata = evaluation_details.flag_metadata
          return nil unless metadata.is_a?(Hash)

          metadata['allocation_key']
        end
      end
    end
  end
end
