# frozen_string_literal: true

require_relative 'ext'
require 'open_feature/sdk'

module Datadog
  module OpenFeature
    # OpenFeature feature flagging provider backed by Datadog Remote Configuration.
    #
    # Requires openfeature-sdk >= 0.5.1 for flag evaluation metrics support.
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

      def hooks
        component = Datadog.send(:components).open_feature
        [
          component&.flag_eval_hook,
          component&.span_enrichment_hook,
        ].compact
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

        # Drive APM span enrichment directly from the evaluation path. The
        # supported OpenFeature Ruby SDK versions do not dispatch provider hooks
        # (`Client#fetch_details` never invokes hooks), so dispatching here is the
        # only reliable way to attach `ffe_*` tags. Guarded so enrichment can
        # never break flag evaluation.
        enrich_span(flag_key, result, evaluation_context)

        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: result.value,
          variant: result.variant,
          reason: result.reason,
          flag_metadata: build_flag_metadata(result),
        )
      rescue => e
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: default_value,
          error_code: Ext::GENERAL,
          error_message: "#{e.class}: #{e.message}",
          reason: Ext::ERROR
        )
      end

      def build_flag_metadata(result)
        original = result.flag_metadata || {}
        metadata = original
        allocation_key = result.allocation_key
        if allocation_key && !allocation_key.empty?
          metadata = metadata.dup
          metadata['__dd_allocation_key'] = allocation_key
        end

        # Thread the split serial id and do-log flag for APM span enrichment.
        #
        # These are read directly off the ResolutionDetails Struct (populated by
        # the libdatadog FFI bindings) rather than from `flag_metadata`, because
        # the native flag-metadata path is currently disabled (FFL-1450). The
        # span-enrichment hook reads these `__dd_` keys from the evaluation
        # details' flag metadata.
        serial_id = result.serial_id
        unless serial_id.nil?
          metadata = metadata.dup if metadata.equal?(original)
          metadata['__dd_split_serial_id'] = serial_id
          metadata['__dd_do_log'] = result.log? || false
        end

        metadata
      end

      # Dispatch span enrichment from the evaluation path in a never-throw
      # wrapper. Reads the split serial id / do-log flag directly off the Datadog
      # `ResolutionDetails` struct (same source as `build_flag_metadata`) and the
      # targeting key off the built evaluation context. A nil hook (gate off or
      # component absent) is a no-op.
      def enrich_span(flag_key, result, evaluation_context)
        hook = span_enrichment_hook
        return unless hook

        hook.capture(
          flag_key: flag_key,
          variant: result.variant,
          value: result.value,
          serial_id: result.serial_id,
          do_log: result.log? || false,
          targeting_key: evaluation_context&.targeting_key,
        )
      rescue => e
        Datadog.logger.debug { "OpenFeature: span enrichment dispatch failed: #{e.class}: #{e.message}" }
      end

      def span_enrichment_hook
        Datadog.send(:components).open_feature&.span_enrichment_hook
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
