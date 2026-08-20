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
        # Keep the policy bound to the evaluator that performs this evaluation.
        observe_full_evaluation_data = false
        evaluator = @evaluator
        observe_full_evaluation_data = evaluator.observe_full_evaluation_data == true

        unless ALLOWED_TYPES.include?(expected_type)
          message = "unknown type #{expected_type.inspect}, allowed types #{ALLOWED_TYPES.join(", ")}"
          result = ResolutionDetails.build_error(
            value: default_value, error_code: Ext::UNKNOWN_TYPE, error_message: message
          )

          return with_observe_full_evaluation_data(result, observe_full_evaluation_data)
        end

        context = evaluation_context&.fields.to_h
        result = evaluator.get_assignment(
          flag_key, default_value: default_value, context: context, expected_type: expected_type
        )

        result = with_observe_full_evaluation_data(result, observe_full_evaluation_data)

        @reporter.report(result, flag_key: flag_key, context: evaluation_context)

        result
      rescue => e
        @telemetry.report(e, description: "OpenFeature: Failed to fetch flag value")

        result = ResolutionDetails.build_error(
          value: default_value, error_code: Ext::GENERAL, error_message: "#{e.class}: #{e.message}"
        )
        with_observe_full_evaluation_data(result, observe_full_evaluation_data == true)
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

      # Stamps observe_full_evaluation_data onto the result metadata so the hook
      # reads it from the event, not live config.
      def with_observe_full_evaluation_data(result, observe_full_evaluation_data)
        return result unless result.respond_to?(:flag_metadata=)

        result = result.dup if result.frozen?
        metadata = result.flag_metadata || {}
        result.flag_metadata = metadata.merge(
          Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => observe_full_evaluation_data
        )
        result
      end
    end
  end
end
