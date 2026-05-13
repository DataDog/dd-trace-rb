# frozen_string_literal: true

require 'opentelemetry/exporter/otlp_logs'

module Datadog
  module OpenTelemetry
    module SDK
      class LogsExporter < ::OpenTelemetry::Exporter::OTLP::Logs::LogsExporter
        METRIC_EXPORT_ATTEMPTS = 'otel.logs_export_attempts'
        METRIC_EXPORT_SUCCESSES = 'otel.logs_export_successes'
        METRIC_EXPORT_FAILURES = 'otel.logs_export_failures'
        METRIC_LOG_RECORDS = 'otel.log_records'
        TELEMETRY_NAMESPACE = 'tracers'
        TELEMETRY_TAGS = {'protocol' => 'http', 'encoding' => 'protobuf'}.freeze

        def export(log_records, timeout: nil)
          telemetry&.inc(TELEMETRY_NAMESPACE, METRIC_EXPORT_ATTEMPTS, 1, tags: TELEMETRY_TAGS)
          telemetry&.inc(TELEMETRY_NAMESPACE, METRIC_LOG_RECORDS, log_records.size, tags: TELEMETRY_TAGS)
          result = super
          metric_name = (result == 0) ? METRIC_EXPORT_SUCCESSES : METRIC_EXPORT_FAILURES
          telemetry&.inc(TELEMETRY_NAMESPACE, metric_name, 1, tags: TELEMETRY_TAGS)
          result
        rescue => e
          Datadog.logger.warn("Failed to export OpenTelemetry Logs: #{e.class}: #{e.message}")
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
