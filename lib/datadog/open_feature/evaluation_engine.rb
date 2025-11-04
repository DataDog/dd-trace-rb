# frozen_string_literal: true

require_relative 'ext'
require_relative 'binding'

module Datadog
  module OpenFeature
    # This class performs the evaluation of the feature flag
    class EvaluationEngine
      attr_accessor :configuration

      ResolutionError = Struct.new(:reason, :code, :message, keyword_init: true)

      ALLOWED_TYPES = %i[boolean string number float integer object].freeze

      def initialize(telemetry, logger: Datadog.logger)
        @telemetry = telemetry
        @logger = logger

        # NOTE: We also could create a no-op evaluator?
        @evaluator = nil
        @configuration = nil
      end

      def fetch_value(flag_key:, expected_type:, evaluation_context: nil)
        if @evaluator.nil?
          return ResolutionError.new(
            code: Ext::PROVIDER_NOT_READY,
            message: 'Waiting for Universal Flag Configuration',
            reason: Ext::INITIALIZING
          )
        end

        unless ALLOWED_TYPES.include?(expected_type)
          message = "unknown type #{expected_type.inspect}, allowed types #{ALLOWED_TYPES.join(',')}"
          return ResolutionError.new(code: Ext::UNKNOWN_TYPE, message: message, reason: Ext::ERROR)
        end

        # NOTE: https://github.com/open-feature/ruby-sdk-contrib/blob/main/providers/openfeature-go-feature-flag-provider/lib/openfeature/go-feature-flag/go_feature_flag_provider.rb#L17
        # In the example from the OpenFeature there is zero trust to the result of the evaluation
        # do we want to go that way?

        @evaluator.get_assignment(flag_key, evaluation_context, expected_type, Time.now.utc.to_i)
      rescue => e
        @telemetry.report(e, description: 'OpenFeature: Failed to fetch value for flag')
        ResolutionError.new(code: Ext::PROVIDER_FATAL, message: e.message, reason: Ext::ERROR)
      end

      # TODO: Put the lock to reconfigure deduplicatoin cache too
      def reconfigure!
        if @configuration.nil?
          @logger.debug('OpenFeature: Configuration is not received, skip reconfiguration')

          return
        end

        @evaluator = Binding::Evaluator.new(@configuration)
      rescue => e
        error_message = 'OpenFeature: Failed to reconfigure, reverting to the previous configuration'

        @logger.error("#{error_message}, error #{e.inspect}")
        @telemetry.report(e, description: error_message)
      end
    end
  end
end
