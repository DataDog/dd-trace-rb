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
      ERROR_MESSAGE_WAITING_FOR_UFC = 'Waiting for User Feature Configuration'

      attr_reader :metadata

      def initialize
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: NAME).freeze
      end

      def init
        # no-op
        @evaluator = OpenFeature.evaluator
      end

      def shutdown
        # no-op
      end

      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        return provider_not_ready_default(default_value) if @evaluator.nil?

        @evaluator.fetch_value(
          flag_key: flag_key,
          expected_type: :boolean,
          evaluation_context: evaluation_context
        )
      end

      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        return provider_not_ready_default(default_value) if @evaluator.nil?

        @evaluator.fetch_value(
          flag_key: flag_key,
          expected_type: :string,
          evaluation_context: evaluation_context
        )
      end

      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        return provider_not_ready_default(default_value) if @evaluator.nil?

        @evaluator.fetch_value(
          flag_key: flag_key,
          expected_type: :number,
          evaluation_context: evaluation_context
        )
      end

      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        return provider_not_ready_default(default_value) if @evaluator.nil?

        @evaluator.fetch_value(
          flag_key: flag_key,
          expected_type: :integer,
          evaluation_context: evaluation_context
        )
      end

      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        return provider_not_ready_default(default_value) if @evaluator.nil?

        @evaluator.fetch_value(
          flag_key: flag_key,
          expected_type: :float,
          evaluation_context: evaluation_context
        )
      end

      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        return provider_not_ready_default(default_value) if @evaluator.nil?

        @evaluator.fetch_value(
          flag_key: flag_key,
          expected_type: :object,
          evaluation_context: evaluation_context
        )
      end

      private

      def provider_not_ready_default(value)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: value,
          error_code: ::OpenFeature::SDK::Provider::ErrorCode::PROVIDER_NOT_READY,
          error_message: ERROR_MESSAGE_WAITING_FOR_UFC,
          reason: ::OpenFeature::SDK::Provider::Reason::DEFAULT
        )
      end
    end
  end
end
