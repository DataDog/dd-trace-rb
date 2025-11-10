# frozen_string_literal: true

require_relative 'evaluation_engine'
require_relative 'exposures'
require_relative 'transport/http'

module Datadog
  module OpenFeature
    # This class is the entry point for the OpenFeature component
    class Component
      attr_reader :telemetry, :engine

      def self.build_open_feature_component(settings, telemetry:)
        return unless settings.respond_to?(:open_feature) && settings.open_feature.enabled

        unless settings.respond_to?(:remote) && settings.remote.enabled
          Datadog.logger.warn('OpenFeature could not be enabled as Remote Configuration is currently disabled. To enable Remote Configuration, see https://docs.datadoghq.com/agent/remote_config')

          return
        end

        new(settings, telemetry: telemetry)
      rescue
        Datadog.logger.warn('OpenFeature is disabled, see logged errors above')

        nil
      end

      def initialize(settings, telemetry:)
        @settings = settings
        @telemetry = telemetry
        @logger = Datadog.logger

        transport = Transport::HTTP.build(agent_settings: nil, logger: @logger)
        @worker = Exposures::Worker.new(settings: settings, transport: transport, logger: @logger)
        @reporter = Exposures::Reporter.new(@worker, telemetry: telemetry, logger: @logger)
        @engine = EvaluationEngine.new(@reporter, telemetry: telemetry, logger: @logger)
      end

      def shutdown!
        @worker&.flush
        @worker&.stop(true)
      end
    end
  end
end
