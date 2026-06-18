# frozen_string_literal: true

require_relative '../tracing/ext'

module Datadog
  module OpenTelemetry
    module SDK
      TELEMETRY_TAGS = {'protocol' => 'http', 'encoding' => 'protobuf'}.freeze

      def self.telemetry_inc(metric_name, value)
        telemetry&.inc(Datadog::Tracing::Ext::TELEMETRY_METRICS_NAMESPACE, metric_name, value, tags: TELEMETRY_TAGS)
      end

      def self.telemetry
        Datadog.send(:components).telemetry
      end
    end
  end
end
