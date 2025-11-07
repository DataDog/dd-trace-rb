# frozen_string_literal: true

require_relative 'ext'
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

      attr_reader :metadata

      def initialize
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: NAME).freeze
      end

      def init
        # no-op
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
        return component_not_configured_default(default_value) if OpenFeature.engine.nil?

        result = OpenFeature.engine.fetch_value(
          flag_key: flag_key,
          expected_type: expected_type,
          evaluation_context: evaluation_context
        )

        if result.key?(:error_code)
          return ::OpenFeature::SDK::Provider::ResolutionDetails.new(
            value: default_value,
            error_code: result[:error_code],
            error_message: result[:error_message],
            reason: result[:reason]
          )
        end

        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: result[:value],
          variant: result[:variant],
          reason: result[:reason],
          flag_metadata: result.fetch(:flag_metadata, {})
        )
      end

      def component_not_configured_default(value)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: value,
          error_code: Ext::PROVIDER_FATAL,
          error_message: "Datadog's OpenFeature component must be configured",
          reason: Ext::ERROR
        )
      end
    end
  end
end
