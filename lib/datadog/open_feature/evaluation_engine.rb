# frozen_string_literal: true

require_relative 'ext'
require_relative 'binding'
require_relative 'noop_evaluator'

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

          return Binding::ResolutionDetails.new(
            error_code: Ext::UNKNOWN_TYPE, error_message: message, reason: Ext::ERROR
          )
        end

        # NOTE: https://github.com/open-feature/ruby-sdk-contrib/blob/main/providers/openfeature-go-feature-flag-provider/lib/openfeature/go-feature-flag/go_feature_flag_provider.rb#L17
        # In the example from the OpenFeature there is zero trust to the result of the evaluation
        # do we want to go that way?

        result = @evaluator.get_assignment(flag_key, evaluation_context, expected_type, Time.now.utc.to_i)
        @reporter.report(result, flag_key: flag_key, context: evaluation_context)

        result
      rescue => e
        @telemetry.report(e, description: 'OpenFeature: Failed to fetch value for flag')

        Binding::ResolutionDetails.new(
          error_code: Ext::PROVIDER_FATAL, error_message: e.message, reason: Ext::ERROR
        )
      end

      def reconfigure!
        @logger.debug('OpenFeature: Removing configuration') if @configuration.nil?

        klass = @configuration.nil? ? NoopEvaluator : Binding::Evaluator
        @mutex.synchronize { @evaluator = klass.new(@configuration) }
      rescue => e
        error_message = 'OpenFeature: Failed to reconfigure, reverting to the previous configuration'

        @logger.error("#{error_message}, error #{e.inspect}")
        @telemetry.report(e, description: error_message)
      end
    end
  end
end
