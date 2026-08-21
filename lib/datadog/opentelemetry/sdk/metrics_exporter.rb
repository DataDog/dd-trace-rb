# frozen_string_literal: true

require "opentelemetry/exporter/otlp_metrics"
require_relative "../sdk"

module Datadog
  module OpenTelemetry
    module SDK
      class MetricsExporter < ::OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter
        METRIC_EXPORT_ATTEMPTS = "otel.metrics_export_attempts"
        METRIC_EXPORT_SUCCESSES = "otel.metrics_export_successes"
        METRIC_EXPORT_FAILURES = "otel.metrics_export_failures"

        def export(metrics, timeout: nil)
          SDK.telemetry_inc(METRIC_EXPORT_ATTEMPTS, 1)
          result = super
          metric_name = (result == 0) ? METRIC_EXPORT_SUCCESSES : METRIC_EXPORT_FAILURES
          SDK.telemetry_inc(metric_name, 1)
          result
        rescue => e
          Datadog.logger.error("Failed to export OpenTelemetry Metrics:  #{e.class}: #{e.message}")
          SDK.telemetry_inc(METRIC_EXPORT_FAILURES, 1)
          raise
        end
      end
    end
  end
end
