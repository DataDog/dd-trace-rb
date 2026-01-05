# frozen_string_literal: true

require 'opentelemetry/exporter/otlp_metrics'

module Datadog
  module OpenTelemetry
    module SDK
      class MetricsExporter < ::OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter
        METRIC_EXPORT_ATTEMPTS = 'otel.metrics_export_attempts'
        METRIC_EXPORT_SUCCESSES = 'otel.metrics_export_successes'
        METRIC_EXPORT_FAILURES = 'otel.metrics_export_failures'
        TELEMETRY_NAMESPACE = 'tracers'
        TELEMETRY_TAGS = {'protocol' => "http", 'encoding' => 'protobuf'}

        def export(metrics, timeout: nil)
          telemetry&.inc(TELEMETRY_NAMESPACE, METRIC_EXPORT_ATTEMPTS, 1, tags: TELEMETRY_TAGS)
          result = super
          metric_name = (result == 0) ? METRIC_EXPORT_SUCCESSES : METRIC_EXPORT_FAILURES
          telemetry&.inc(TELEMETRY_NAMESPACE, metric_name, 1, tags: TELEMETRY_TAGS)
          result
        rescue => e
          Datadog.logger.error("Failed to export OpenTelemetry Metrics:  #{e.class}: #{e}")
          telemetry&.inc(TELEMETRY_NAMESPACE, METRIC_EXPORT_FAILURES, 1, tags: TELEMETRY_TAGS)
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
