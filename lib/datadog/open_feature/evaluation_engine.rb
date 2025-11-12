# frozen_string_literal: true

require_relative 'ext'
require_relative 'noop_evaluator'
require_relative 'resolution_details'

module Datadog
  module OpenFeature
    # This class performs the evaluation of the feature flag
    class EvaluationEngine
      attr_accessor :configuration
      attr_reader :reporter

      ALLOWED_TYPES = %i[boolean string number float integer object].freeze

      def initialize(reporter, telemetry:, logger: Datadog.logger)
        @reporter = reporter
        @telemetry = telemetry
        @logger = logger

        @mutex = Mutex.new
        @evaluator = NoopEvaluator.new(nil)
        @configuration = nil
      end

      def fetch_value(flag_key:, expected_type:, evaluation_context: nil)
        unless ALLOWED_TYPES.include?(expected_type)
          message = "unknown type #{expected_type.inspect}, allowed types #{ALLOWED_TYPES.join(', ')}"

          return ResolutionDetails.new(
            error_code: Ext::UNKNOWN_TYPE,
            error_message: message,
            reason: Ext::ERROR,
            log?: false,
            error?: true
          )
        end

        result = @evaluator.get_assignment(flag_key, evaluation_context, expected_type)
        @reporter.report(result, flag_key: flag_key, context: evaluation_context)

        result
      rescue => e
        @telemetry.report(e, description: 'OpenFeature: Failed to fetch value for flag')

        ResolutionDetails.new(
          error_code: Ext::PROVIDER_FATAL,
          error_message: e.message,
          reason: Ext::ERROR,
          error?: true,
          log?: false
        )
      end

      def reconfigure!
        @logger.debug('OpenFeature: Removing configuration') if @configuration.nil?

        @mutex.synchronize do
          @evaluator = NoopEvaluator.new(@configuration)
        end
      rescue => e
        error_message = 'OpenFeature: Failed to reconfigure, reverting to the previous configuration'

        @logger.error("#{error_message}, error #{e.inspect}")
        @telemetry.report(e, description: error_message)

        raise e
      end
    end
  end
end
