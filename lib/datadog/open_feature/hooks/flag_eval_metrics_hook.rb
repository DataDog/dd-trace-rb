# frozen_string_literal: true

require_relative "../ext"

module Datadog
  module OpenFeature
    module Hooks
      # Records flag evaluation metrics via OpenTelemetry hook
      #
      # OpenFeature SDK 0.5.1 is the first release that defines Hooks::Hook and runs hooks.
      class FlagEvalMetricsHook
        # Include the Hook module if available (SDK >= 0.5.1) for interface documentation
        # and default implementations of other hook methods (before, after, error)
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        # Returns true if the OpenFeature SDK supports hooks (>= 0.5.1)
        def self.available?
          !!defined?(::OpenFeature::SDK::Hooks::Hook)
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
          return unless metadata.is_a?(Hash)

          metadata[Ext::METADATA_ALLOCATION_KEY]
        end
      end
    end
  end
end
