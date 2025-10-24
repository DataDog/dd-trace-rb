# frozen_string_literal: true

require 'open_feature/sdk'

module Datadog
  module OpenFeature
    # Example
    #
    #   require 'open_feature/sdk'
    #   require 'datadog/open_feature/provider'
    #
    #   Datadog.configure do |config|
    #     config.open_feature.enabled = true
    #   end
    #
    #   OpenFeature::SDK.configure do |config|
    #     config.set_provider(Datadog::OpenFeature::Provider.new)
    #   end
    #
    #   client = OpenFeature::SDK.build_client
    #   client.fetch_string_value(flag_key: 'banner', default_value: 'default')
    class Provider
      NAME = 'Datadog Feature Flagging Provider'
      ERROR_MESSAGE_COMPONENT_NOT_CONFIGURED = "Datadog's OpenFeature component must be configured"

      attr_reader :metadata

      def initialize
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: NAME).freeze
      end

      def init
        @evaluator = OpenFeature.evaluator
      end

      def shutdown
        # no-op
      end

      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value: default_value, expected_type: :boolean, evaluation_context: evaluation_context)
      end

      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value: default_value, expected_type: :string, evaluation_context: evaluation_context)
      end

      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value: default_value, expected_type: :number, evaluation_context: evaluation_context)
      end

      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value: default_value, expected_type: :integer, evaluation_context: evaluation_context)
      end

      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value: default_value, expected_type: :float, evaluation_context: evaluation_context)
      end

      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        evaluate(flag_key, default_value: default_value, expected_type: :object, evaluation_context: evaluation_context)
      end

      private

      def evaluate(flag_key, default_value:, expected_type:, evaluation_context:)
        return component_not_configured_default(default_value) if @evaluator.nil?

        result = @evaluator.fetch_value(
          flag_key: flag_key,
          expected_type: expected_type,
          evaluation_context: evaluation_context
        )

        if result.is_a?(Evaluator::ResolutionError)
          return ::OpenFeature::SDK::Provider::ResolutionDetails.new(
            value: default_value,
            error_code: result.code,
            error_message: result.message,
            reason: result.reason
          )
        end

        result
      end

      def component_not_configured_default(value)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: value,
          error_code: ::OpenFeature::SDK::Provider::ErrorCode::PROVIDER_FATAL,
          error_message: ERROR_MESSAGE_COMPONENT_NOT_CONFIGURED,
          reason: ::OpenFeature::SDK::Provider::Reason::ERROR
        )
      end
    end
  end
end
