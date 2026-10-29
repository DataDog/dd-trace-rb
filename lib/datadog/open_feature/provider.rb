# frozen_string_literal: true

require_relative "ext"
require_relative "../open_feature"
require_relative "../core/utils/time"
require_relative "hooks/evaluation_telemetry_opt_out_hook"
require "open_feature/sdk"

module Datadog
  module OpenFeature
    # OpenFeature feature flagging provider backed by Datadog configuration delivery.
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
    #   Feature Flags use agentless configuration delivery by default. To use
    #   Remote Configuration delivery instead, configure the source explicitly.
    #
    #   ```ruby
    #   # FILE: initializers/datadog.rb
    #   Datadog.configure do |config|
    #     config.remote.enabled = true
    #     config.feature_flags.configuration_source = "remote_config"
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
      include ::OpenFeature::SDK::Provider::EventEmitter

      NAME = "Datadog Feature Flagging Provider"
      INITIALIZATION_CANCELLED_MESSAGE = "Feature Flags provider initialization was cancelled by shutdown"
      SDK_EMITS_INITIALIZATION_EVENTS = Gem::Version.new(::OpenFeature::SDK::VERSION) < Gem::Version.new("0.7.0")
      private_constant :SDK_EMITS_INITIALIZATION_EVENTS

      attr_reader :metadata

      def initialize(enable_evaluation_telemetry_opt_out_parameter: nil)
        @enable_evaluation_telemetry_opt_out_parameter = case enable_evaluation_telemetry_opt_out_parameter
        when nil
          Datadog.configuration.feature_flags.evaluation_telemetry_per_subject_opt_out_enabled
        when true, false
          enable_evaluation_telemetry_opt_out_parameter
        else
          raise ArgumentError, "enable_evaluation_telemetry_opt_out_parameter expects true, false, or nil"
        end
        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: NAME).freeze
        @initialization_mutex = Mutex.new
        @initializing = false
        @initialization_thread = nil
        @initialization_returned = false
        @awaiting_ready_after_fork = false
        @initialization_failed = false
        @provider_error_observed = false
        @ready_pending = false
        @ready_dispatch_claimed = false
        @stale_emitted = false
        @stale_pending = false
        @error_handler = nil
        @initialization_ready_handler = nil
        @waiting_component = nil
        @shutdown = false
      end

      def init
        @initialization_mutex.synchronize do
          raise INITIALIZATION_CANCELLED_MESSAGE if @shutdown

          @initializing = true
          @initialization_thread = Thread.current
          @initialization_returned = false
          @awaiting_ready_after_fork = false
          @initialization_failed = false
          @provider_error_observed = false
          @ready_pending = false
          @ready_dispatch_claimed = false
          @stale_emitted = false
          @stale_pending = false
        end
        Datadog.logger.debug { "Feature Flags: provider initialization started" }
        ready_handler_installed = install_initialization_ready_handler

        component, failure = OpenFeature.activate_provider(self)
        cancel_initialization_if_shutdown!
        fail_initialization(component, failure || "Feature Flags component could not be activated") unless component

        @initialization_mutex.synchronize do
          raise INITIALIZATION_CANCELLED_MESSAGE if @shutdown

          @waiting_component = component
        end
        # Shutdown publishes this flag through the component lock; taking our mutex here would invert lock order.
        wait_result = component.wait_for_configuration { @shutdown }
        cancel_initialization_if_shutdown!

        case wait_result
        when Component::CONFIGURATION_READY
          if SDK_EMITS_INITIALIZATION_EVENTS
            @initialization_mutex.synchronize { @initializing = false } unless ready_handler_installed
          else
            emit_state_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY)
            provider_ready
          end
          Datadog.logger.debug { "Feature Flags: provider initialized successfully" }
        when Component::CONFIGURATION_TIMEOUT
          message = "Feature Flags provider initialization timed out while waiting for configuration"
          Datadog.logger.error(message)
          fail_initialization(component, message)
        else
          fail_initialization(component, "Feature Flags provider initialization stopped before configuration arrived")
        end
      rescue => error
        prepare_initialization_failure(component) if @initialization_mutex.synchronize { @initializing }
        unless SDK_EMITS_INITIALIZATION_EVENTS || shutdown?
          emit_state_event(
            ::OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR,
            error_code: ::OpenFeature::SDK::Provider::ErrorCode::GENERAL,
            message: error.message,
          )
          provider_error
        end
        raise
      ensure
        @initialization_mutex.synchronize do
          @waiting_component = nil
          @initialization_returned = true
          @initialization_thread = nil unless @initialization_ready_handler || @error_handler
        end
      end

      def emits_lifecycle_events?
        true
      end

      def shutdown
        # @type var error_handler: Provider::provider_event_handler?
        error_handler = nil
        # @type var initialization_ready_handler: Provider::provider_event_handler?
        initialization_ready_handler = nil
        waiting_component = nil #: Component?
        @initialization_mutex.synchronize do
          return if @shutdown

          @shutdown = true
          @initializing = false
          @initialization_thread = nil
          error_handler = @error_handler
          initialization_ready_handler = @initialization_ready_handler
          waiting_component = @waiting_component
          @error_handler = nil
          @initialization_ready_handler = nil
        end

        waiting_component&.wake_configuration_waiters
        ::OpenFeature::SDK.remove_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR, error_handler) if error_handler
        if initialization_ready_handler
          ::OpenFeature::SDK.remove_handler(
            ::OpenFeature::SDK::ProviderEvent::PROVIDER_READY,
            initialization_ready_handler,
          )
        end
        OpenFeature.deactivate_provider(self)
        Datadog.logger.debug { "Feature Flags: provider shut down" }
      end

      def hooks
        component = Datadog.send(:components).open_feature
        telemetry_hooks = [
          component&.flag_eval_metrics_hook,
          component&.flag_eval_evp_hook,
        ].compact
        if @enable_evaluation_telemetry_opt_out_parameter
          telemetry_hooks = telemetry_hooks.map { |hook| Hooks::EvaluationTelemetryOptOutHook.new(hook) }
        end

        [*telemetry_hooks, component&.debug_logging_hook].compact
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

      def after_fork(component)
        handler = @initialization_mutex.synchronize do
          return if @shutdown || !@initializing || @initialization_thread&.alive?

          @initializing = false
          @initialization_thread = nil
          @waiting_component = nil
          @awaiting_ready_after_fork = true
          @stale_pending = false
          previous_handler = @initialization_ready_handler
          @initialization_ready_handler = nil
          previous_handler
        end
        if handler
          ::OpenFeature::SDK.remove_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY, handler)
        end
        configuration_changed(Component::CONFIGURATION_READY) if component&.configuration_received?
      end

      def fail_initialization(component, message)
        prepare_initialization_failure(component)
        cancel_initialization_if_shutdown!
        # Non-blocking set_provider surfaces this only as a PROVIDER_ERROR event.
        Datadog.logger.debug { "Feature Flags: provider failed to initialize: #{message}" }
        raise message.to_s
      end

      def prepare_initialization_failure(component)
        cancelled, initialization_ready_handler = @initialization_mutex.synchronize do
          handler = @initialization_ready_handler
          @initialization_ready_handler = nil
          @stale_pending = false
          @initializing = false
          if @shutdown
            [true, handler]
          else
            @initialization_failed = true
            @ready_pending ||= !!component&.configuration_received?
            [false, handler]
          end
        end
        if initialization_ready_handler
          ::OpenFeature::SDK.remove_handler(
            ::OpenFeature::SDK::ProviderEvent::PROVIDER_READY,
            initialization_ready_handler,
          )
        end
        return if cancelled

        install_error_handler
      end

      def cancel_initialization_if_shutdown!
        cancelled = @initialization_mutex.synchronize do
          @initializing = false if @shutdown
          @shutdown
        end
        raise INITIALIZATION_CANCELLED_MESSAGE if cancelled
      end

      def shutdown?
        @initialization_mutex.synchronize { @shutdown }
      end

      def install_initialization_ready_handler
        return false unless SDK_EMITS_INITIALIZATION_EVENTS && configuration_attached?

        handler = @initialization_mutex.synchronize do
          return false if @shutdown
          return true if @initialization_ready_handler

          @initialization_ready_handler = ->(details) { provider_ready if initialization_event?(details) }
        end
        ::OpenFeature::SDK.add_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY, handler)

        cancelled = @initialization_mutex.synchronize { @shutdown }
        ::OpenFeature::SDK.remove_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY, handler) if cancelled
        return false if cancelled

        true
      end

      def install_error_handler
        return unless SDK_EMITS_INITIALIZATION_EVENTS && configuration_attached?

        handler = @initialization_mutex.synchronize do
          return if @shutdown

          @error_handler ||= ->(details) { provider_error if initialization_event?(details) }
        end
        ::OpenFeature::SDK.add_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR, handler)

        cancelled = @initialization_mutex.synchronize { @shutdown }
        ::OpenFeature::SDK.remove_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR, handler) if cancelled
      end

      def initialization_event?(details)
        # SDKs before 0.7 emit their initialization event synchronously after init returns.
        @initialization_mutex.synchronize do
          @initialization_returned && Thread.current.equal?(@initialization_thread) && details[:provider_name] == NAME
        end
      end

      def provider_error
        handler, emit_ready = @initialization_mutex.synchronize do
          handler = @error_handler
          @error_handler = nil
          @initialization_thread = nil
          if @shutdown
            [handler, false]
          else
            @provider_error_observed = true
            emit_ready = @ready_pending && !@ready_dispatch_claimed
            @ready_dispatch_claimed = true if emit_ready
            [handler, emit_ready]
          end
        end
        ::OpenFeature::SDK.remove_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_ERROR, handler) if handler
        emit_state_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY) if emit_ready
      end

      def provider_ready
        handler, emit_stale = @initialization_mutex.synchronize do
          handler = @initialization_ready_handler
          @initialization_ready_handler = nil
          @initializing = false
          @initialization_thread = nil
          if @stale_pending && !@shutdown
            @stale_pending = false
            @stale_emitted = true
            [handler, true]
          else
            [handler, false]
          end
        end
        ::OpenFeature::SDK.remove_handler(::OpenFeature::SDK::ProviderEvent::PROVIDER_READY, handler) if handler
        emit_state_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_STALE) if emit_stale
      end

      def configuration_changed(event)
        event_type = @initialization_mutex.synchronize do
          if @shutdown
            nil
          elsif event == Component::CONFIGURATION_READY
            if @initializing
              @ready_pending = true
              @stale_pending = false
              nil
            elsif @awaiting_ready_after_fork
              @awaiting_ready_after_fork = false
              @stale_emitted = false
              ::OpenFeature::SDK::ProviderEvent::PROVIDER_READY
            elsif @initialization_failed && !@provider_error_observed
              @stale_emitted = false
              @ready_pending = true
              nil
            elsif @stale_emitted
              @stale_emitted = false
              ::OpenFeature::SDK::ProviderEvent::PROVIDER_READY
            elsif @initialization_failed
              if @provider_error_observed && !@ready_dispatch_claimed
                @ready_dispatch_claimed = true
                ::OpenFeature::SDK::ProviderEvent::PROVIDER_READY
              else
                @ready_pending = true
                nil
              end
            end
          elsif event == Component::CONFIGURATION_CHANGED && !@initializing
            ::OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED
          elsif event == Component::CONFIGURATION_LOST
            @ready_pending = false
            if @initializing
              @stale_pending = true
              nil
            else
              @stale_emitted = true
              ::OpenFeature::SDK::ProviderEvent::PROVIDER_STALE
            end
          end
        end

        emit_state_event(event_type) if event_type
      end

      def emit_state_event(event_type, details = {})
        log_state_event(event_type)
        emit_event(event_type, details)
      end

      def log_state_event(event_type)
        logger = Datadog.logger
        logger.debug do
          availability = case event_type
          when ::OpenFeature::SDK::ProviderEvent::PROVIDER_READY
            "; configuration is available"
          when ::OpenFeature::SDK::ProviderEvent::PROVIDER_STALE
            "; configuration is no longer available"
          end
          "Feature Flags: provider emitted #{event_type}#{availability}"
        end
      end

      def evaluate(flag_key, default_value:, expected_type:, evaluation_context:)
        # Stamp evaluation entry time once, here on the eval thread. The EVP path uses this for
        # accurate first/last_evaluation bounds instead of a later hook-fire clock read.
        eval_time_ms = (Core::Utils::Time.now.to_f * 1000).to_i
        flag_meta = nil

        engine = OpenFeature.engine
        if engine.nil?
          log_component_not_configured(flag_key, expected_type)
          return component_not_configured_default(default_value, eval_time_ms)
        end

        result = fetch_engine_value(engine, flag_key, default_value, expected_type, evaluation_context)

        # Build metadata before branching so provider-returned details carry eval-entry time.
        flag_meta = build_flag_metadata(result, eval_time_ms)

        if result.error?
          return sdk_error_details(default_value, result.error_code, result.error_message, result.reason, flag_meta)
        end

        # Drive APM span enrichment directly from the evaluation path. This is the only reliable
        # way to attach `ffe_*` tags across all supported OpenFeature SDK versions, since older
        # SDKs do not dispatch provider hooks. Guarded so enrichment can never break evaluation.
        unless evaluation_telemetry_opted_out?(evaluation_context)
          enrich_span(flag_key, result, evaluation_context)
        end

        sdk_success_details(result, flag_meta)
      rescue => e
        error_message = "#{e.class}: #{e.message}"
        error_result = Datadog::OpenFeature::ResolutionDetails.build_error(
          value: default_value,
          error_code: Ext::GENERAL,
          error_message: error_message
        )
        error_flag_meta = flag_meta
        error_flag_meta ||= build_flag_metadata(
          error_result, eval_time_ms || (Core::Utils::Time.now.to_f * 1000).to_i
        )

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
        metadata[Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA] =
          metadata[Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA] == true
        allocation_key = result.allocation_key
        metadata[Ext::METADATA_ALLOCATION_KEY] = allocation_key if allocation_key && !allocation_key.empty?

        # Eval-time stamped at provider entry; the EVP hook reads 'dd.eval.timestamp_ms' for
        # accurate first/last_evaluation bounds (it falls back to hook-fire time when absent).
        metadata["dd.eval.timestamp_ms"] = eval_time_ms

        metadata
      end

      # Dispatch span enrichment from the evaluation path in a never-throw
      # wrapper. Reads the split serial id / do-log flag directly off the Datadog
      # `ResolutionDetails` struct and the targeting key off the built evaluation
      # context. A nil hook (gate off or component absent) is a no-op.
      def enrich_span(flag_key, result, evaluation_context)
        hook = span_enrichment_hook
        return unless hook

        # Hook resolved first so the common gate-off path short-circuits without
        # resolving the tracer. With the gate on but no active trace there is
        # nowhere to attach tags, so skip before building the capture call.
        return unless Datadog::Tracing.active_trace

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

      # No component means no DebugLoggingHook and no raw-data warning, so only non-raw fields are logged.
      def log_component_not_configured(flag_key, expected_type)
        logger = Datadog.logger
        logger.debug do
          "Feature Flags: provider returned the default value for #{flag_key.inspect} (type=#{expected_type}): " \
            "the Feature Flags component is not active; see the provider initialization logs " \
            "(error_code=#{Ext::PROVIDER_FATAL})"
        end
      end

      def evaluation_telemetry_opted_out?(evaluation_context)
        @enable_evaluation_telemetry_opt_out_parameter &&
          Hooks::EvaluationTelemetryOptOutHook.opted_out?(evaluation_context)
      end

      def component_not_configured_default(value, eval_time_ms)
        ::OpenFeature::SDK::Provider::ResolutionDetails.new(
          value: value,
          error_code: Ext::PROVIDER_FATAL,
          error_message: "Datadog's OpenFeature component must be configured",
          reason: Ext::ERROR,
          flag_metadata: {
            "dd.eval.timestamp_ms" => eval_time_ms,
            Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => false,
          }
        )
      end
    end
  end
end
