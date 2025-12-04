# frozen_string_literal: true

require_relative 'ext'
require 'open_feature/sdk'

module Datadog
  module OpenFeature
    # OpenFeature feature flagging provider backed by Datadog Remote Configuration.
    #
    # Implementation follows the OpenFeature contract of Provider SDK.
    # For details see:
    #   - https://github.com/open-feature/ruby-sdk/blob/v0.4.1/README.md#develop-a-provider
    #   - https://github.com/open-feature/ruby-sdk/blob/v0.4.1/lib/open_feature/sdk/provider/no_op_provider.rb
    #
    # In the example below you can see how to configure the OpenFeature SDK
    # https://github.com/open-feature/ruby-sdk to use the Datadog feature flags provider.
    #
    # Example:
    #
    #   Make sure to enable Remote Configuration and OpenFeature in the Datadog configuration.
    #
    #   ```ruby
    #   # FILE: initializers/datadog.rb
    #   Datadog.configure do |config|
    #     config.remote.enabled = true
    #     config.open_feature.enabled = true
    #   end
    #   ```
    #
    #   And configure the OpenFeature SDK to use the Datadog feature flagging provider.
    #
    #   ```ruby
    #   # FILE: initializers/open_feature.rb
    #   require 'open_feature/sdk'
    #   require 'datadog/open_feature/provider'
    #
    #   OpenFeature::SDK.configure do |config|
    #     config.set_provider(Datadog::OpenFeature::Provider.new)
    #   end
    #   ```
    #
    #   Now you can create OpenFeature SDK client and use it to fetch feature flag values.
    #
    #   ```ruby
    #   client = OpenFeature::SDK.build_client
    #   context = OpenFeature::SDK::EvaluationContext.new('email' => 'john.doe@gmail.com')
    #
    #   client.fetch_string_value(
    #     flag_key: 'banner', default_value: 'Greetings!', evaluation_context: context
    #   )
    #   # => 'Welcome back!'
    #   ```
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
        engine = OpenFeature.engine
        return component_not_configured_default(default_value) if engine.nil?

        result = engine.fetch_value(
          flag_key,
          default_value: default_value,
          expected_type: expected_type,
          evaluation_context: evaluation_context
        )

        if result.error?
          return ::OpenFeature::SDK::Provider::ResolutionDetails.new(
            value: default_value,
            error_code: result.error_code,
            error_message: result.error_message,
            reason: result.reason
          )
        end

        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: result.value,
          variant: result.variant,
          reason: result.reason,
          flag_metadata: result.flag_metadata
        )
      rescue => e
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: default_value,
          error_code: Ext::GENERAL,
          error_message: "#{e.class}: #{e.message}",
          reason: Ext::ERROR
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
