# frozen_string_literal: true

module Datadog
  module OpenFeature
    class Evaluator
      attr_writer :ufc

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
        # into default value

        # NOTE: https://github.com/open-feature/ruby-sdk-contrib/blob/main/providers/openfeature-go-feature-flag-provider/lib/openfeature/go-feature-flag/go_feature_flag_provider.rb#L17
        # In the example from the OpenFeature there is zero trust to the result of the evaluation
        # do we want to go that way?

        # TODO: Implement binding call
        # <binding>.get_assignment(@configuration, flag_key, evaluation_context, expected_type, Time.now.utc)

        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: generate(expected_type),
          reason: 'hardcoded',
          variant: 'hardcoded'
        )
      end

      def reconfigure!
        # TODO: Call to the binding to get configuration created
        # config = datadog_ffe::rules_based::UniversalFlagConfig::from_json(ufc)
        # @configuration = datadog_ffe::rules_based::Configuration::from_server_response(config)

        # TODO: Remove
        @reconfigured = true
      rescue => e
        error_message = 'OpenFeature failed to reconfigure, reverting to the previous configuration'

        Datadog.logger.error("#{error_message}, error #{e.inspect}")
        @telemetry.report(e, description: error_message)
      end

      private

      # TODO: Remove
      def generate(expected_type)
        case expected_type
        when :boolean then @reconfigured ? true : false
        when :string then @reconfigured ? 'hello' : 'goodbye'
        when :number then @reconfigured ? 9000 : 0
        when :integer then @reconfigured ? 42 : -42
        when :float then @reconfigured ? 36.6 : 39.5
        when :object then @reconfigured ? [1, 2, 3] : {one: :two}
        end
      end
    end
  end
end
