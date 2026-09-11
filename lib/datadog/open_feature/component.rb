# frozen_string_literal: true

require_relative "transport"
require_relative "evaluation_engine"
require_relative "../core/utils/time"
require_relative "configuration/source"
require_relative "exposures/buffer"
require_relative "exposures/worker"
require_relative "exposures/deduplicator"
require_relative "exposures/reporter"
require_relative "metrics/flag_eval_metrics"
require_relative "flag_evaluation/writer"
require_relative "hooks/flag_eval_metrics_hook"
require_relative "hooks/flag_eval_evp_hook"
require_relative "hooks/span_enrichment_hook"

module Datadog
  module OpenFeature
    # This class is the entry point for the OpenFeature component
    class Component
      CONFIGURATION_READY = :ready
      CONFIGURATION_TIMEOUT = :timeout
      CONFIGURATION_SHUTDOWN = :shutdown
      CONFIGURATION_CHANGED = :changed

      attr_reader :engine, :flag_eval_metrics_hook, :flag_eval_evp_hook, :span_enrichment_hook

      def self.build(settings, agent_settings, resolution:, on_configuration_change:, logger:, telemetry:)
        return unless resolution.enabled?

        if RUBY_ENGINE != "ruby"
          message = "OpenFeature could not be enabled as MRI is required, " \
            "but running on #{RUBY_ENGINE.inspect}"

          logger.warn(message)
          return
        end

        if (libdatadog_api_failure = Core::LIBDATADOG_API_FAILURE)
          message = "OpenFeature could not be enabled as `libdatadog` is not loaded: " \
            "#{libdatadog_api_failure.inspect}. For help solving this issue, " \
            "please contact Datadog support at https://docs.datadoghq.com/help/."

          logger.warn(message)
          return
        end

        new(
          settings,
          agent_settings,
          on_configuration_change: on_configuration_change,
          logger: logger,
          telemetry: telemetry,
        )
      end

      def initialize(settings, agent_settings, logger:, telemetry:, on_configuration_change: nil)
        transport = Transport::HTTP.build(agent_settings: agent_settings, logger: logger)
        @worker = Exposures::Worker.new(settings: settings, transport: transport, telemetry: telemetry, logger: logger)

        reporter = Exposures::Reporter.new(@worker, telemetry: telemetry, logger: logger)
        @engine = EvaluationEngine.new(reporter, telemetry: telemetry, logger: logger)

        @telemetry = telemetry
        @logger = logger
        @settings = settings
        @agent_settings = agent_settings
        @on_configuration_change = on_configuration_change
        @flag_eval_metrics_hook = create_flag_eval_metrics_hook
        @flag_eval_evp_hook = create_flag_eval_evp_hook
        @span_enrichment_hook = create_span_enrichment_hook

        @configuration_mutex = Mutex.new
        @configuration_condition = ConditionVariable.new
        @configuration_received = false
        @configuration_shutdown = false
      end

      def reconfigure!(configuration)
        event = @configuration_mutex.synchronize do
          return if @configuration_shutdown

          previously_received = @configuration_received
          @engine.reconfigure!(configuration)
          @configuration_received = !configuration.nil?
          @configuration_condition.broadcast

          if @configuration_received
            previously_received ? CONFIGURATION_CHANGED : CONFIGURATION_READY
          end
        end

        @on_configuration_change&.call(event) if event
      end

      def wait_for_configuration
        timeout_seconds = @settings.open_feature.initialization_timeout_ms / 1000.0
        deadline = Core::Utils::Time.get_time + timeout_seconds

        @configuration_mutex.synchronize do
          loop do
            return CONFIGURATION_READY if @configuration_received
            return CONFIGURATION_SHUTDOWN if @configuration_shutdown

            remaining = deadline - Core::Utils::Time.get_time
            return CONFIGURATION_TIMEOUT unless remaining.positive?

            @configuration_condition.wait(@configuration_mutex, remaining)
          end
        end
      end

      def configuration_received?
        @configuration_mutex.synchronize { @configuration_received }
      end

      def shutdown!
        @configuration_mutex.synchronize do
          @configuration_shutdown = true
          @configuration_condition.broadcast
        end

        @worker.graceful_shutdown
        @flag_eval_evp_writer&.stop
        # Symmetric teardown: drop any accumulated span-enrichment state and
        # subscriptions (Ruby CLAUDE.md mandates closing resources).
        @span_enrichment_hook&.shutdown
      end

      private

      def create_flag_eval_metrics_hook
        return unless Hooks::FlagEvalMetricsHook.available?

        metrics = Metrics::FlagEvalMetrics.new(telemetry: @telemetry, logger: @logger)
        Hooks::FlagEvalMetricsHook.new(metrics)
      end

      # Killswitch: DD_FLAGGING_EVALUATION_COUNTS_ENABLED (default on) gates only the EVP path.
      # Read through the datadog config registry, not raw ENV.
      def create_flag_eval_evp_hook
        return unless @settings.open_feature.evaluation_counts_enabled
        return unless Hooks::FlagEvalEVPHook.available?

        evp_transport = Transport::HTTP.build_flagevaluations(
          agent_settings: @agent_settings,
          logger: @logger,
        )
        @flag_eval_evp_writer = FlagEvaluation::Writer.new(transport: evp_transport, logger: @logger, telemetry: @telemetry)
        Hooks::FlagEvalEVPHook.new(@flag_eval_evp_writer)
      end

      # Construct the span-enrichment hook only when the opt-in gate is on, so
      # there is no idle per-span overhead when disabled.
      def create_span_enrichment_hook
        return unless @settings.open_feature.span_enrichment_enabled

        store = Hooks::SpanEnrichmentHook::SpanEnrichmentStateStore.new
        Hooks::SpanEnrichmentHook.new(store, logger: @logger)
      end
    end
  end
end
