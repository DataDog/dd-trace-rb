# frozen_string_literal: true

require_relative 'binding'

module Datadog
  module OpenFeature
    # NOTE: This class is a glue between libdatadog evaluation binding and
    #       provider. It should not contain any SDK code, but rather define its own
    class Evaluator
      attr_accessor :ufc_json


      ResolutionError = Struct.new(:reason, :code, :message, keyword_init: true)

      # TODO: Extract? when binding is ready (or reuse from binding)
      PROVIDER_NOT_READY = 'PROVIDER_NOT_READY'
      PROVIDER_FATAL = 'PROVIDER_FATAL'

      UNKNOWN_TYPE = 'UNKNOWN_TYPE'
      ERROR_MESSAGE_NOT_READY = 'Waiting for Universal Flag Configuration'
      INITIALIZING = 'INITIALIZING'
      ERROR = 'ERROR'

      ALLOWED_TYPES = %i[boolean string number float integer object].freeze

      def initialize(telemetry)
        @telemetry = telemetry
        # NOTE: We also could create a no-op evaluator?
        @evaluator = nil
        @ufc_json = nil
      end

      def fetch_value(flag_key:, expected_type:, evaluation_context: nil)
        if @evaluator.nil?
          return ResolutionError.new(code: PROVIDER_NOT_READY, message: ERROR_MESSAGE_NOT_READY, reason: INITIALIZING)
        end

        unless ALLOWED_TYPES.include?(expected_type)
          message = "unknown type #{expected_type.inspect}, allowed types #{ALLOWED_TYPES.join(",")}"
          return ResolutionError.new(code: UNKNOWN_TYPE, message: message, reason: ERROR)
        end

        # NOTE: https://github.com/open-feature/ruby-sdk-contrib/blob/main/providers/openfeature-go-feature-flag-provider/lib/openfeature/go-feature-flag/go_feature_flag_provider.rb#L17
        # In the example from the OpenFeature there is zero trust to the result of the evaluation
        # do we want to go that way?

        @evaluator.get_assignment(@configuration, flag_key, evaluation_context, expected_type, Time.now.utc.to_i)
      rescue => e
        @telemetry.report(e, description: 'OpenFeature: Failed to fetch value for flag')
        ResolutionError.new(reason: ERROR, code: PROVIDER_FATAL, message: e.message)
      end

      def reconfigure!
        @evaluator = Datadog::OpenFeature::Binding::Evaluator.new(@ufc_json)
      rescue => e
        error_message = 'OpenFeature failed to reconfigure, reverting to the previous configuration'

        Datadog.logger.error("#{error_message}, error #{e.inspect}")
        @telemetry.report(e, description: error_message)
      end
    end
  end
end
