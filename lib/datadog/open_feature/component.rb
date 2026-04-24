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
      attr_reader :engine

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
        @flag_eval_hook = nil
        @hook_mutex = Mutex.new
      end

      # Lazy initialization of the flag eval hook.
      # The hook depends on the OpenFeature SDK gem which may not be loaded when
      # the component is first initialized (due to Rails initializer ordering).
      def flag_eval_hook
        @hook_mutex.synchronize do
          return @flag_eval_hook if @flag_eval_hook

          @flag_eval_hook = create_flag_eval_hook
        end
      end

      def shutdown!
        @worker.graceful_shutdown
      end

      private

      def create_flag_eval_hook
        return nil unless defined?(::OpenFeature::SDK::Hooks::Hook)

        require_relative 'hooks/flag_eval_hook'
        metrics = Metrics::FlagEvalMetrics.new(telemetry: @telemetry, logger: @logger)
        Hooks::FlagEvalHook.new(metrics)
      rescue LoadError, NameError
        nil
      end
    end
  end
end
