# frozen_string_literal: true

require_relative 'evaluation_engine'
require_relative 'exposures'
require_relative 'transport/http'

module Datadog
  module OpenFeature
    # This class is the entry point for the OpenFeature component
    class Component
      attr_reader :telemetry, :engine

      def self.build(settings, agent_settings, logger:, telemetry:)
        return unless settings.respond_to?(:open_feature) && settings.open_feature.enabled

        unless settings.respond_to?(:remote) && settings.remote.enabled
          logger.warn('OpenFeature: Could not be enabled without Remote Configuration Management available')

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

        transport = Transport::HTTP.exposures(agent_settings: agent_settings, logger: logger)
        @worker = Exposures::Worker.new(transport: transport, logger: logger)
        @reporter = Exposures::Reporter.new(worker: @worker, logger: logger)
        @engine = EvaluationEngine.new(@reporter, telemetry: telemetry, logger: logger)
      end

      def shutdown!
        @reporter&.clear
        return unless defined?(@worker) && @worker

        @worker.flush
        @worker.stop(true)
      end
    end
  end
end
