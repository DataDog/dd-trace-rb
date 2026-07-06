# frozen_string_literal: true

require 'opentelemetry/exporter/otlp_logs'
require_relative '../sdk'

module Datadog
  module OpenTelemetry
    module SDK
      class LogsExporter < ::OpenTelemetry::Exporter::OTLP::Logs::LogsExporter
        METRIC_EXPORT_ATTEMPTS = 'otel.logs_export_attempts'
        METRIC_EXPORT_SUCCESSES = 'otel.logs_export_successes'
        METRIC_EXPORT_FAILURES = 'otel.logs_export_failures'
        METRIC_LOG_RECORDS = 'otel.log_records'

        def export(log_records, timeout: nil)
          SDK.telemetry_inc(METRIC_EXPORT_ATTEMPTS, 1)
          SDK.telemetry_inc(METRIC_LOG_RECORDS, log_records.size)
          result = super
          metric_name = (result == 0) ? METRIC_EXPORT_SUCCESSES : METRIC_EXPORT_FAILURES
          SDK.telemetry_inc(metric_name, 1)
          result
        rescue => e
          Datadog.logger.warn("Failed to export OpenTelemetry Logs: #{e.class}: #{e.message}")
          SDK.telemetry_inc(METRIC_EXPORT_FAILURES, 1)
          raise
        end
      end
    end
  end
end
