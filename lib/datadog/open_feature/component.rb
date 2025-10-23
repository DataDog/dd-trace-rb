# frozen_string_literal: true

require_relative 'evaluator'

module Datadog
  module OpenFeature
    class Component
      attr_reader :telemetry, :evaluator

      def self.build_open_feature_component(settings, telemetry:)
        return unless settings.respond_to?(:open_feature) && settings.open_feature.enabled

        new(telemetry: telemetry)
      rescue
        Datadog.logger.warn('OpenFeature is disabled, see logged errors above')

        nil
      end

      def initialize(telemetry:)
        @telemetry = telemetry
        @evaluator = Evaluator.new(telemetry)
      end

      def shutdown!
        # no-op
      end
    end
  end
end
