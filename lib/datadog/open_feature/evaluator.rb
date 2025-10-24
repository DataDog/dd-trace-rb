# frozen_string_literal: true

module Datadog
  module OpenFeature
    # NOTE: This class is a glue between libdatadog evaluation binding and
    #       provider. It should not contain any SDK code, but rather define its own
    class Evaluator
      attr_writer :ufc

      # NOTE: This structure will come from the binding
      #       and will copy the structure of the OpenFeature SDK
      #       I will pile them up here before extracting
      ResolutionDetails = Struct.new(
        :value, :reason, :variant, :error_code, :error_message, :flag_metadata, keyword_init: true
      )
      ResolutionError = Struct.new(
        :reason, :code, :message
      )

      PROVIDER_NOT_READY = 'PROVIDER_NOT_READY'
      PROVIDER_FATAL = "PROVIDER_FATAL"

      ERROR_MESSAGE_NOT_READY = 'Waiting for Universal Flag Configuration'
      INITIALIZING = 'INITIALIZING'
      ERROR = "ERROR"

      def initialize(telemetry)
        @telemetry = telemetry
        @configuration = nil
        @ufc = nil
      end

      def fetch_value(flag_key:, expected_type:, evaluation_context: nil)
        # NOTE: @configuration exists as instance variable and should be
        #       converter to None if missing, that would allow us to have
        #       default values while waiting for RC to populate UFC
        # NOTE: it makes sense to hide `now` timestamp because it's not a public interface
        #       and would not change if we use UTC by default
        # datadog_ffe::rules_based::get_assignment(Some(&configuration), flag_key, context, None, now);
        # or
        # config.eval_flag(flag_key, subject, expected_type, now)
        #
        # configuration: Option<&Configuration>,
        # flag_key: &str,
        # subject: &EvaluationContext,
        # expected_type: Option<VariationType>,
        # now: DateTime<Utc>,
        #
        # NOTE: If configuration is missing it will return Ok(None) which we suppose to convert
        # into default value by the provider, so we should return here an error instead
        # and do a shortcur avoiding call to the binding.
        if @configuration.nil?
          return ResolutionError.new(code: PROVIDER_NOT_READY, message: ERROR_MESSAGE_NOT_READY, reason: INITIALIZING)
        end

        # NOTE: https://github.com/open-feature/ruby-sdk-contrib/blob/main/providers/openfeature-go-feature-flag-provider/lib/openfeature/go-feature-flag/go_feature_flag_provider.rb#L17
        # In the example from the OpenFeature there is zero trust to the result of the evaluation
        # do we want to go that way?

        # TODO: Implement binding call
        # <binding>.get_assignment(@configuration, flag_key, evaluation_context, expected_type, Time.now.utc)

        ResolutionDetails.new(
          value: generate(expected_type),
          reason: 'hardcoded',
          variant: 'hardcoded'
        )
      rescue => e
        @telemetry.report(e, 'OpenFeature: Failed to fetch value for flag')

        ResolutionError.new(
          reason: ERROR,
          code: PROVIDER_FATAL,
          message: e.message
        )
      end

      def reconfigure!
        # TODO: Call to the binding to get configuration created
        # config = datadog_ffe::rules_based::UniversalFlagConfig::from_json(ufc)
        # @configuration = datadog_ffe::rules_based::Configuration::from_server_response(config)

        # TODO: Replace with binding class
        @configuration = { ufc: @ufc }

        # FIXME: If we have to clean the binding class to release memory because
        #        of the binding unable to GC unused class we will need to guard
        #        @configuration reading
      rescue => e
        error_message = 'OpenFeature failed to reconfigure, reverting to the previous configuration'

        Datadog.logger.error("#{error_message}, error #{e.inspect}")
        @telemetry.report(e, description: error_message)
      end

      private

      # TODO: Remove
      def generate(expected_type)
        case expected_type
        when :boolean then true
        when :string then 'hello'
        when :number then 9000
        when :integer then 42
        when :float then 36.6
        when :object then [1, 2, 3]
        end
      end
    end
  end
end
