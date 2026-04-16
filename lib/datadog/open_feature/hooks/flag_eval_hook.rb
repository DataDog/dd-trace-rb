# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Hooks
      # Records flag evaluation metrics via OpenTelemetry hook
      class FlagEvalHook
        include ::OpenFeature::SDK::Hooks::Hook

        def initialize(metrics)
          @metrics = metrics
        end

        def finally(hook_context:, evaluation_details:, hints:)
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
