# frozen_string_literal: true

require_relative 'evaluation_engine'

module Datadog
  module OpenFeature
    class Component
      attr_reader :telemetry, :engine

      def self.build_open_feature_component(settings, telemetry:)
        return unless settings.respond_to?(:open_feature) && settings.open_feature.enabled

        new(telemetry: telemetry)
      rescue
        Datadog.logger.warn('OpenFeature is disabled, see logged errors above')

        nil
      end

      def initialize(telemetry:)
        @telemetry = telemetry
        @engine = EvaluationEngine.new(telemetry, logger: Datadog.logger)
      end

      def shutdown!
        # no-op
      end
    end
  end
end
