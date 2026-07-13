# frozen_string_literal: true

require_relative 'transport'
require_relative 'evaluation_engine'
require_relative 'exposures/buffer'
require_relative 'exposures/worker'
require_relative 'exposures/deduplicator'
require_relative 'exposures/reporter'
require_relative 'metrics/flag_eval_metrics'

module Datadog
  module OpenFeature
    # This class is the entry point for the OpenFeature component
    class Component
      attr_reader :engine, :flag_eval_metrics_hook, :flag_eval_evp_hook, :span_enrichment_hook

      def self.build(settings, agent_settings, logger:, telemetry:)
        return unless settings.respond_to?(:open_feature) && settings.open_feature.enabled

        unless settings.respond_to?(:remote) && settings.remote.enabled
          message = 'OpenFeature could not be enabled as Remote Configuration is currently disabled. ' \
            'To enable Remote Configuration, see https://docs.datadoghq.com/remote_configuration/.'

          logger.warn(message)
          return
        end

        if RUBY_ENGINE != 'ruby'
          message = 'OpenFeature could not be enabled as MRI is required, ' \
            "but running on #{RUBY_ENGINE.inspect}"

          logger.warn(message)
          return
        end

        if (libdatadog_api_failure = Core::LIBDATADOG_API_FAILURE)
          message = 'OpenFeature could not be enabled as `libdatadog` is not loaded: ' \
            "#{libdatadog_api_failure.inspect}. For help solving this issue, " \
            'please contact Datadog support at https://docs.datadoghq.com/help/.'

          logger.warn(message)
          return
        end

        new(settings, agent_settings, logger: logger, telemetry: telemetry)
      end

      def initialize(settings, agent_settings, logger:, telemetry:)
        transport = Transport::HTTP.build(agent_settings: agent_settings, logger: logger)
        @worker = Exposures::Worker.new(settings: settings, transport: transport, telemetry: telemetry, logger: logger)

        reporter = Exposures::Reporter.new(@worker, telemetry: telemetry, logger: logger)
        @engine = EvaluationEngine.new(reporter, telemetry: telemetry, logger: logger)

        @telemetry = telemetry
        @logger = logger
        @settings = settings
        @agent_settings = agent_settings
        @flag_eval_metrics_hook = create_flag_eval_metrics_hook
        @flag_eval_evp_hook = create_flag_eval_evp_hook
        @span_enrichment_hook = create_span_enrichment_hook
      end

      def shutdown!
        @worker.graceful_shutdown
        @flag_eval_evp_writer&.stop
        # Symmetric teardown: drop any accumulated span-enrichment state and
        # subscriptions (Ruby CLAUDE.md mandates closing resources).
        @span_enrichment_hook&.shutdown
      end

      private

      def create_flag_eval_metrics_hook
        require_relative 'hooks/flag_eval_metrics_hook'
        return unless Hooks::FlagEvalMetricsHook.available?

        metrics = Metrics::FlagEvalMetrics.new(telemetry: @telemetry, logger: @logger)
        Hooks::FlagEvalMetricsHook.new(metrics)
      rescue LoadError
        nil
      end

      # Killswitch: DD_FLAGGING_EVALUATION_COUNTS_ENABLED (default on) gates only the EVP path.
      # Read through the datadog config registry, not raw ENV.
      def create_flag_eval_evp_hook
        return unless @settings.open_feature.evaluation_counts_enabled

        require_relative 'hooks/flag_eval_evp_hook'
        return unless Hooks::FlagEvalEVPHook.available?

        evp_transport = Transport::HTTP.build_flagevaluations(
          agent_settings: @agent_settings,
          logger: @logger,
        )
        require_relative 'flag_evaluation/writer'
        @flag_eval_evp_writer = FlagEvaluation::Writer.new(transport: evp_transport, logger: @logger, telemetry: @telemetry)
        Hooks::FlagEvalEVPHook.new(@flag_eval_evp_writer)
      rescue LoadError
        nil
      end

      # Construct the span-enrichment hook only when the opt-in gate is on, so
      # there is no idle per-span overhead when disabled.
      def create_span_enrichment_hook
        return unless @settings.open_feature.span_enrichment_enabled

        require_relative 'hooks/span_enrichment_hook'
        return unless Hooks::SpanEnrichmentHook.available?

        store = Hooks::SpanEnrichmentHook::AccumulatorStore.new
        Hooks::SpanEnrichmentHook.new(store)
      rescue LoadError
        nil
      end
    end
  end
end
