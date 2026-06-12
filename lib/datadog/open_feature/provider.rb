# frozen_string_literal: true

require_relative 'ext'
require 'open_feature/sdk'

module Datadog
  module OpenFeature
    # OpenFeature feature flagging provider backed by Datadog Remote Configuration.
    #
    # Requires openfeature-sdk >= 0.5.1 for flag evaluation metrics support.
    #
    # Hook lifecycle note: the Ruby openfeature-sdk (through at least 0.5.x) does not invoke
    # provider hooks during evaluation. FlagEvalEVPHook is registered for forward compatibility
    # but is also called directly from #evaluate to ensure EVP flag-evaluation events are
    # emitted regardless of SDK version. See call_evp_hook for details.
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

      # Lightweight duck-typed wrappers used to call FlagEvalEVPHook#finally directly,
      # bypassing the openfeature-sdk hook lifecycle (which is not invoked in sdk <= 0.5.x).
      #
      # The hook accesses:
      #   hook_context.flag_key
      #   hook_context.evaluation_context&.targeting_key
      #   hook_context.evaluation_context&.attributes  (Hash of non-targeting_key fields)
      #   evaluation_details.flag_metadata
      #   evaluation_details.variant
      #   evaluation_details.reason
      #
      # ::OpenFeature::SDK::EvaluationContext exposes #fields (all fields including targeting_key)
      # and #targeting_key, but NOT #attributes. EvpEvalContext adapts fields -> attributes.
      EvpEvalContext = Struct.new(:targeting_key, :attributes)
      HookContext = Struct.new(:flag_key, :evaluation_context)
      HookDetails = Struct.new(:variant, :reason, :flag_metadata)

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
        otel_hook = component&.flag_eval_hook
        evp_hook  = component&.flag_eval_evp_hook
        [otel_hook, evp_hook].compact
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

        # Build metadata before branching so EVP and the success path share one call.
        flag_meta = build_flag_metadata(result)

        # Drive EVP hook directly: the Ruby openfeature-sdk does not invoke provider hooks,
        # so we call it here to cover both success and error paths (finally semantics).
        call_evp_hook(flag_key, result, evaluation_context, flag_meta)

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
          flag_metadata: flag_meta,
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
        metadata = result.flag_metadata || {}
        allocation_key = result.allocation_key
        if allocation_key && !allocation_key.empty?
          metadata = metadata.dup
          metadata['__dd_allocation_key'] = allocation_key
        end

        metadata
      end

      def component_not_configured_default(value)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: value,
          error_code: Ext::PROVIDER_FATAL,
          error_message: "Datadog's OpenFeature component must be configured",
          reason: Ext::ERROR
        )
      end

      # Call the EVP hook directly — the Ruby openfeature-sdk (through at least 0.5.x) does not
      # invoke provider hooks during evaluation, so we must drive it ourselves. The hook is still
      # registered via #hooks for forward compatibility with future SDK versions that do support
      # the full hook lifecycle. This method is idempotent: if the killswitch is on or the
      # component is absent, flag_eval_evp_hook is nil and this is a no-op.
      #
      # ::OpenFeature::SDK::EvaluationContext has #fields and #targeting_key but NOT #attributes.
      # We adapt it into EvpEvalContext which provides the #attributes interface the hook expects.
      def call_evp_hook(flag_key, result, evaluation_context, flag_metadata)
        hook = Datadog.send(:components).open_feature&.flag_eval_evp_hook
        return unless hook

        evp_ctx = if evaluation_context
          targeting_key = evaluation_context.targeting_key
          # attributes: all fields except targeting_key (mirrors how exposures builds context)
          attrs = evaluation_context.fields.reject { |k, _| k == ::OpenFeature::SDK::EvaluationContext::TARGETING_KEY }
          EvpEvalContext.new(targeting_key, attrs)
        end

        hook.finally(
          hook_context: HookContext.new(flag_key, evp_ctx),
          evaluation_details: HookDetails.new(result.variant, result.reason, flag_metadata),
        )
      rescue => e
        # Best-effort: EVP emission must never raise into the evaluation hot path.
        Datadog.logger.debug { "OpenFeature EVP: call_evp_hook error: #{e.class}: #{e.message}" }
      end
    end
  end
end
