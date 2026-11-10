# frozen_string_literal: true

require "open_feature/sdk"

require_relative "ext"
require_relative "split_features"
require_relative "../core/utils/only_once"

module Datadog
  module OpenFeature
    # An OpenFeature hook that hands each completed evaluation to a callback, with the Datadog
    # exposure decision, so an application can record exposures in its own data store.
    #
    # Register it on the OpenFeature API, a client, or an evaluation:
    #
    #   hook = Datadog::OpenFeature::ExposureHook.new do |evaluation|
    #     next unless evaluation.should_send?
    #
    #     exposure_queue << [evaluation.flag_key, evaluation.targeting_key, evaluation.variant, evaluation.features]
    #   end
    #   OpenFeature::SDK.configure { |config| config.hooks << hook }
    #
    # The callback runs on the evaluation thread for every evaluation of a directly registered
    # Datadog provider, including errors and repeats. It must not block or do I/O. An exception
    # raised by the callback never affects the evaluation: the first one is logged at warn level,
    # later ones at debug level.
    #
    # @public_api
    class ExposureHook
      include ::OpenFeature::SDK::Hooks::Hook if defined?(::OpenFeature::SDK::Hooks::Hook)

      # A completed evaluation and its Datadog exposure decision.
      #
      # @public_api
      class Evaluation
        attr_reader :evaluation_context, :evaluation_details

        def initialize(hook_context, evaluation_details)
          @flag_key = hook_context.flag_key
          @evaluation_context = hook_context.evaluation_context
          @evaluation_details = evaluation_details
          metadata = evaluation_details.flag_metadata
          @metadata = metadata.is_a?(Hash) ? metadata : SplitFeatures::EMPTY
        end

        attr_reader :flag_key

        def variant
          @evaluation_details.variant
        end

        def allocation_key
          allocation_key = @metadata[Ext::METADATA_ALLOCATION_KEY]
          allocation_key if allocation_key.is_a?(String)
        end

        def split_serial_id
          serial_id = @metadata[Ext::METADATA_SPLIT_SERIAL_ID]
          serial_id if serial_id.is_a?(Integer)
        end

        def targeting_key
          @evaluation_context&.targeting_key
        end

        # True for a successful evaluation of an allocation that logs exposures, repeats included.
        def exposure?
          @evaluation_details.error_code.nil? &&
            @evaluation_details.reason != Ext::ERROR &&
            !variant.nil? &&
            !allocation_key.nil? &&
            @metadata[Ext::METADATA_DO_LOG] == true
        end

        # True when this subject was already exposed to the same allocation, variant and serial id.
        def cache_hit?
          exposure? && @metadata[Ext::METADATA_EXPOSURE_CACHE_HIT] == true
        end

        # True for a new or changed exposure: the exposures the provider selects for reporting to Datadog while
        # DD_FEATURE_FLAGS_EXPOSURES_DATADOG_LOGGING_ENABLED is on. This does not confirm delivery.
        def should_send?
          exposure? && @metadata[Ext::METADATA_EXPOSURE_CACHE_HIT] == false
        end

        # The selected split's features, such as "holdout.key"; values are String, Float or true/false.
        #
        # @return [Hash{String => String, Float, Boolean}] frozen, empty when the split has none
        def features
          @features ||= SplitFeatures.read(@metadata, Ext::METADATA_FEATURE_PREFIX)
        end
      end

      def initialize(callback = nil, &block)
        raise ArgumentError, "pass either a callback or a block, not both" if callback && block

        callable = callback || block
        raise ArgumentError, "callback must respond to #call" unless callable.respond_to?(:call)

        @callback = callable
        @failure_warning = Core::Utils::OnlyOnce.new
        @unsupported_provider_warning = Core::Utils::OnlyOnce.new
      end

      def finally(hook_context:, evaluation_details:, **_opts)
        return unless datadog_provider?(hook_context)

        @callback.call(Evaluation.new(hook_context, evaluation_details))
      rescue StandardError, ScriptError => e
        log_callback_failure(hook_context, e)
      end

      private

      # A composed provider does not run the Datadog provider's hooks, so no exposure decision exists.
      def datadog_provider?(hook_context)
        return true if hook_context.provider_metadata&.name == Ext::PROVIDER_NAME

        @unsupported_provider_warning.run do
          Datadog.logger.warn(
            "Feature Flags: ExposureHook requires a directly registered Datadog provider; " \
            "callbacks are skipped for other providers",
          )
        end
        false
      end

      def log_callback_failure(hook_context, error)
        message = "Feature Flags: ExposureHook callback failed for #{hook_context.flag_key.inspect}: #{error.class}"
        warned = false
        @failure_warning.run do
          warned = true
          Datadog.logger.warn("#{message}; later failures are logged at debug level")
        end
        Datadog.logger.debug { "#{message}: #{error.message}" } unless warned
      rescue StandardError, ScriptError
        # The logger or the error's own message raised; the evaluation must still complete.
        nil
      end
    end
  end
end
