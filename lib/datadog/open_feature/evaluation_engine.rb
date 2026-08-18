# frozen_string_literal: true

require_relative "ext"
require_relative "noop_evaluator"
require_relative "native_evaluator"
require_relative "resolution_details"

module Datadog
  module OpenFeature
    # This class performs the evaluation of the feature flag
    class EvaluationEngine
      # Steep: https://github.com/soutaro/steep/issues/1880
      ReconfigurationError = Class.new(StandardError) # steep:ignore IncompatibleAssignment

      ALLOWED_TYPES = %i[boolean string number float integer object].freeze

      def initialize(reporter, telemetry:, logger:)
        @reporter = reporter
        @telemetry = telemetry
        @logger = logger

        @evaluator = NoopEvaluator.new(nil)
      end

      def fetch_value(flag_key, default_value:, expected_type:, evaluation_context: nil)
        unless ALLOWED_TYPES.include?(expected_type)
          message = "unknown type #{expected_type.inspect}, allowed types #{ALLOWED_TYPES.join(", ")}"
          return ResolutionDetails.build_error(
            value: default_value, error_code: Ext::UNKNOWN_TYPE, error_message: message
          )
        end

        # Snapshot the evaluator once so the result and the consent stamped onto
        # it come from the same configuration. A `reconfigure!` swap between
        # reading `@evaluator` and calling `get_assignment` would otherwise let a
        # later Remote Config update retroactively change the consent applied to
        # an evaluation that ran under the previous config.
        evaluator = @evaluator
        context = evaluation_context&.fields.to_h
        result = evaluator.get_assignment(
          flag_key, default_value: default_value, context: context, expected_type: expected_type
        )

        stamp_consent!(result, evaluator.observe_full_evaluation_data)

        @reporter.report(result, flag_key: flag_key, context: evaluation_context)

        result
      rescue => e
        @telemetry.report(e, description: "OpenFeature: Failed to fetch flag value")

        ResolutionDetails.build_error(
          value: default_value, error_code: Ext::GENERAL, error_message: "#{e.class}: #{e.message}"
        )
      end

      # Consent value from the UFC the current evaluator holds. Returns false
      # before configuration is present or when the value is absent, null, or
      # wrong-typed (the privacy-preserving default).
      def observe_full_evaluation_data
        @evaluator.observe_full_evaluation_data
      end

      # NOTE: In a currect implementation configuration is expected to be a raw
      #       JSON string containing feature flags (straight from the remote config)
      #       in the format expected by `libdatadog` without any modifications
      def reconfigure!(configuration)
        if configuration.nil?
          @logger.debug("OpenFeature: Removing configuration")

          return @evaluator = NoopEvaluator.new(configuration)
        end

        @evaluator = NativeEvaluator.new(configuration)
      rescue => e
        message = "OpenFeature: Failed to reconfigure, reverting to the previous configuration"

        @logger.error("#{message}, #{e.class}: #{e.message}")
        @telemetry.report(e, description: "#{message} (#{e.class})")

        raise ReconfigurationError, "#{e.class}: #{e.message}"
      end

      private

      # Stamps the consent snapshot onto the result's flag metadata so the hook
      # reads it from the event, not from live config. No-ops for result types
      # without a `flag_metadata` writer (none in the current SDK paths).
      def stamp_consent!(result, consent)
        return unless result.respond_to?(:flag_metadata=)

        metadata = result.flag_metadata || {}
        result.flag_metadata = metadata.merge(Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => consent)
      end
    end
  end
end
