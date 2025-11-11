# frozen_string_literal: true

require_relative 'evaluation_engine'
require_relative 'exposures/buffer'
require_relative 'exposures/worker'
require_relative 'exposures/deduplicator'
require_relative 'exposures/reporter'
require_relative 'transport/http'

module Datadog
  module OpenFeature
    # This class is the entry point for the OpenFeature component
    class Component
      attr_reader :telemetry, :engine

      def self.build(settings, agent_settings, logger:, telemetry:)
        return unless settings.open_feature.enabled

        unless settings.remote.enabled
          logger.warn('OpenFeature could not be enabled as Remote Configuration is currently disabled. To enable Remote Configuration, see https://docs.datadoghq.com/agent/remote_config')

          return
        end

        new(settings, agent_settings, logger: logger, telemetry: telemetry)
      rescue
        Datadog.logger.warn('OpenFeature is disabled, see logged errors above')

        nil
      end

      def initialize(settings, agent_settings, logger:, telemetry:)
        @settings = settings
        @agent_settings = agent_settings
        @logger = logger
        @telemetry = telemetry

        transport = Transport::HTTP.build(agent_settings: agent_settings, logger: logger)
        @worker = Exposures::Worker.new(settings: settings, transport: transport, logger: logger)
        @reporter = Exposures::Reporter.new(@worker, telemetry: telemetry, logger: logger)
        @engine = EvaluationEngine.new(@reporter, telemetry: telemetry, logger: logger)
      end

      def shutdown!
        @worker&.flush
        @worker&.stop(true)
      end
    end
  end
end
