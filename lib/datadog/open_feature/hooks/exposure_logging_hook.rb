# frozen_string_literal: true

require_relative "../ext"
require_relative "../split_features"

module Datadog
  module OpenFeature
    module Hooks
      # Makes the one exposure decision of an evaluation: records it in the exposure cache,
      # sends new or changed exposures to Datadog, and stamps the verdict into the flag metadata
      # as `__dd_exposure_cache_hit` for hooks that run after it.
      #
      # It runs at the finally stage because an application after hook can still raise and turn
      # the result into the default value. The SDK runs provider finally hooks before application
      # ones, so ExposureHook callbacks see the final verdict.
      class ExposureLoggingHook
        include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

        def self.available?
          !!defined?(::OpenFeature::SDK::Hooks::Hook)
        end

        def initialize(reporter, telemetry:, logger:)
          @reporter = reporter
          @telemetry = telemetry
          @logger = logger
        end

        def finally(hook_context:, evaluation_details:, **_opts)
          return if evaluation_details.error_code || evaluation_details.reason == Ext::ERROR

          # The SDK may hand hooks frozen copies; the verdict goes into the details' own metadata.
          metadata = evaluation_details.resolution_details[:flag_metadata]
          return unless metadata.is_a?(Hash) && !metadata.frozen?
          return unless metadata[Ext::METADATA_DO_LOG] == true

          allocation_key = metadata[Ext::METADATA_ALLOCATION_KEY]
          variant = evaluation_details.variant
          context = hook_context.evaluation_context
          return unless allocation_key.is_a?(String) && variant && context

          metadata[Ext::METADATA_EXPOSURE_CACHE_HIT] = @reporter.record(
            flag_key: hook_context.flag_key,
            allocation_key: allocation_key,
            variant: variant,
            serial_id: metadata[Ext::METADATA_SPLIT_SERIAL_ID],
            context: context,
            features: SplitFeatures.read(metadata, Ext::METADATA_EXPOSURE_FEATURE_PREFIX),
          )
        rescue => e
          # Exposure reporting must never change the evaluation result.
          @logger.debug { "OpenFeature: Failed to report exposure: #{e.class}: #{e.message}" }
          @telemetry.report(e, description: "OpenFeature: Failed to report exposure")
        end
      end
    end
  end
end
