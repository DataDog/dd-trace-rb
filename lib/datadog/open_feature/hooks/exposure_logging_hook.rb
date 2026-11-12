# frozen_string_literal: true

require_relative "../exposure_resolution_details"

module Datadog
  module OpenFeature
    module Hooks
      class ExposureLoggingHook
        def finally(hook_context:, evaluation_details:, **_options)
          return if evaluation_details.nil? || evaluation_details.error_code || evaluation_details.reason == "ERROR"

          details = evaluation_details.resolution_details
          details.report_exposures if details.is_a?(ExposureResolutionDetails)
        # Exposure reporting must never replace the SDK's finalized result.
        rescue => e
          Datadog.logger.debug { "OpenFeature: exposure reporting failed: #{e.class}" }
        end
      end
    end
  end
end
