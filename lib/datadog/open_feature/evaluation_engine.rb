# frozen_string_literal: true

require_relative 'ext'
require_relative 'noop_evaluator'
require_relative 'native_evaluator'
require_relative 'resolution_details'

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

        context = evaluation_context&.fields.to_h
        result = @evaluator.get_assignment(
          flag_key, default_value: default_value, context: context, expected_type: expected_type
        )

        @reporter.report(result, flag_key: flag_key, context: evaluation_context)

        result
      rescue => e
        @telemetry.report(e, description: 'OpenFeature: Failed to fetch flag value')

        ResolutionDetails.build_error(
          value: default_value, error_code: Ext::GENERAL, error_message: e.message
        )
      end

      # NOTE: In a currect implementation configuration is expected to be a raw
      #       JSON string containing feature flags (straight from the remote config)
      #       in the format expected by `libdatadog` without any modifications
      def reconfigure!(configuration)
        if configuration.nil?
          @logger.debug('OpenFeature: Removing configuration')

          return @evaluator = NoopEvaluator.new(configuration)
        end

        @evaluator = NativeEvaluator.new(configuration)
      rescue => e
        message = 'OpenFeature: Failed to reconfigure, reverting to the previous configuration'

        @logger.error("#{message}, #{e.class}: #{e.message}")
        @telemetry.report(e, description: "#{message} (#{e.class})")

        raise ReconfigurationError, e.message
      end
    end
  end
end
