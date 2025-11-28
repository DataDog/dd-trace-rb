# frozen_string_literal: true

require 'opentelemetry/exporter/otlp_metrics'

module Datadog
  module OpenTelemetry
    module SDK
      class MetricsExporter < ::OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter
        METRIC_EXPORT_ATTEMPTS = 'otel.metrics_export_attempts'
        METRIC_EXPORT_SUCCESSES = 'otel.metrics_export_successes'
        METRIC_EXPORT_FAILURES = 'otel.metrics_export_failures'

        def initialize(endpoint:, timeout:, headers:, protocol:)
          super(endpoint: endpoint, timeout: timeout, headers: headers)
          @telemetry_tags = {'protocol' => protocol, 'encoding' => 'protobuf'}
        end

        def export(metrics, timeout: nil)
          telemetry.inc('tracers', METRIC_EXPORT_ATTEMPTS, 1, tags: @telemetry_tags)
          result = super
          metric_name = (result == 0) ? METRIC_EXPORT_SUCCESSES : METRIC_EXPORT_FAILURES
          telemetry.inc('tracers', metric_name, 1, tags: @telemetry_tags)
          result
        rescue => e
          Datadog.logger.error("Failed to export OpenTelemetry Metrics:  #{e.class}: #{e}")
          telemetry.inc('tracers', METRIC_EXPORT_FAILURES, 1, tags: @telemetry_tags)
          raise
        end

        private

        def telemetry
          Datadog.send(:components).telemetry
        end
      end
    end
  end
end
