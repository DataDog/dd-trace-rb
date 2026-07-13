# frozen_string_literal: true

require_relative 'ext'
require_relative '../core/utils/time'
require 'open_feature/sdk'

module Datadog
  module OpenFeature
    # OpenFeature feature flagging provider backed by Datadog Remote Configuration.
    #
    # Requires openfeature-sdk >= 0.5.1 for flag evaluation metrics and EVP hook support.
    #
    # Hook lifecycle note: FlagEvalEVPHook is returned from #hooks so EVP uses the SDK-final
    # EvaluationDetails. This matches FlagEvalMetricsHook and records defaults/errors produced
    # by OpenFeature hook failures or post-provider type validation.
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
          component&.flag_eval_metrics_hook,
          component&.flag_eval_evp_hook,
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
        # Stamp evaluation entry time once, here on the eval thread. The EVP path uses this for
        # accurate first/last_evaluation bounds instead of a later hook-fire clock read.
        eval_time_ms = (Core::Utils::Time.now.to_f * 1000).to_i

        engine = OpenFeature.engine
        return component_not_configured_default(default_value, eval_time_ms) if engine.nil?

        result = fetch_engine_value(engine, flag_key, default_value, expected_type, evaluation_context)

        # Build metadata before branching so provider-returned details carry eval-entry time.
        flag_meta = build_flag_metadata(result, eval_time_ms)

        if result.error?
          return sdk_error_details(default_value, result.error_code, result.error_message, result.reason, flag_meta)
        end

        # Drive APM span enrichment directly from the evaluation path. This is the only reliable
        # way to attach `ffe_*` tags across all supported OpenFeature SDK versions, since older
        # SDKs do not dispatch provider hooks. Guarded so enrichment can never break evaluation.
        enrich_span(flag_key, result, evaluation_context)

        sdk_success_details(result, flag_meta)
      rescue => e
        error_message = "#{e.class}: #{e.message}"
        error_result = Datadog::OpenFeature::ResolutionDetails.build_error(
          value: default_value,
          error_code: Ext::GENERAL,
          error_message: error_message
        )
        error_flag_meta = build_flag_metadata(error_result, eval_time_ms || (Core::Utils::Time.now.to_f * 1000).to_i)

        sdk_error_details(default_value, Ext::GENERAL, error_message, Ext::ERROR, error_flag_meta)
      end

      def fetch_engine_value(engine, flag_key, default_value, expected_type, evaluation_context)
        engine.fetch_value(
          flag_key,
          default_value: default_value,
          expected_type: expected_type,
          evaluation_context: evaluation_context
        )
      end

      def sdk_success_details(result, flag_meta)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: result.value,
          variant: result.variant,
          reason: result.reason,
          flag_metadata: flag_meta,
        )
      end

      def sdk_error_details(default_value, error_code, error_message, reason, flag_meta = {})
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: default_value,
          error_code: error_code,
          error_message: error_message,
          reason: reason,
          flag_metadata: flag_meta
        )
      end

      def build_flag_metadata(result, eval_time_ms)
        metadata = result.flag_metadata&.dup || {}
        allocation_key = result.allocation_key
        metadata['__dd_allocation_key'] = allocation_key if allocation_key && !allocation_key.empty?

        # Eval-time stamped at provider entry; the EVP hook reads 'dd.eval.timestamp_ms' for
        # accurate first/last_evaluation bounds (it falls back to hook-fire time when absent).
        metadata['dd.eval.timestamp_ms'] = eval_time_ms

        # Thread the split serial id and do-log flag for APM span enrichment.
        #
        # These are read directly off the ResolutionDetails Struct (populated by
        # the libdatadog FFI bindings) rather than from `flag_metadata`, because
        # the native flag-metadata path is currently disabled. The
        # span-enrichment hook reads these `__dd_` keys from the evaluation
        # details' flag metadata.
        serial_id = result.serial_id
        unless serial_id.nil?
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

      def component_not_configured_default(value, eval_time_ms)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: value,
          error_code: Ext::PROVIDER_FATAL,
          error_message: "Datadog's OpenFeature component must be configured",
          reason: Ext::ERROR,
          flag_metadata: {'dd.eval.timestamp_ms' => eval_time_ms}
        )
      end
    end
  end
end
