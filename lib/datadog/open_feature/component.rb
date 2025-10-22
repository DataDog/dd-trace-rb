# frozen_string_literal: true

module Datadog
  module OpenFeature
    class Component
      attr_reader :telemetry

      def self.build_open_feature_component(settings, telemetry:)
        return unless settings.respond_to?(:open_feature) && settings.open_feature.enabled

        unless settings.remote.enabled
          logger.warn('OpenFeature could not be enabled as Remote Configuration is currently disabled. To enable Remote Configuration, see https://docs.datadoghq.com/agent/remote_config')

          return
        end

        new(settings, agent_settings, logger: logger, telemetry: telemetry)
      rescue
        Datadog.logger.warn('OpenFeature is disabled, see logged errors above')
        nil
      end

      def initialize(telemetry:)
        @telemetry = telemetry

        transport = Transport::HTTP.build(agent_settings: agent_settings, logger: logger)
        @worker = Exposures::Worker.new(settings: settings, transport: transport, logger: logger)
        @reporter = Exposures::Reporter.new(@worker, telemetry: telemetry, logger: logger)
        @engine = EvaluationEngine.new(@reporter, telemetry: telemetry, logger: logger)
      end

      def shutdown!
        # no-op
      end
    end
  end
end
