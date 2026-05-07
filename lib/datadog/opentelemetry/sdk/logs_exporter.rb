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

        def initialize(protocol: nil, **kwargs)
          @telemetry_tags = compute_telemetry_tags(protocol)
          # Parent expects endpoint:, timeout:, headers: (and optional SSL/cert args); do not pass protocol
          super(**kwargs.except(:protocol))
        end

        def export(log_records, timeout: nil)
          telemetry&.inc(TELEMETRY_NAMESPACE, METRIC_EXPORT_ATTEMPTS, 1, tags: @telemetry_tags)
          telemetry&.inc(TELEMETRY_NAMESPACE, METRIC_LOG_RECORDS, log_records.size, tags: @telemetry_tags)
          result = super
          metric_name = (result == 0) ? METRIC_EXPORT_SUCCESSES : METRIC_EXPORT_FAILURES
          telemetry&.inc(TELEMETRY_NAMESPACE, metric_name, 1, tags: @telemetry_tags)
          result
        rescue => e
          Datadog.logger.error("Failed to export OpenTelemetry Logs: #{e.class}: #{e.message}")
          telemetry&.inc(TELEMETRY_NAMESPACE, METRIC_EXPORT_FAILURES, 1, tags: @telemetry_tags)
          raise
        end

        private

        def compute_telemetry_tags(protocol)
          case protocol
          when 'grpc'
            {'protocol' => 'grpc', 'encoding' => 'protobuf'}
          when 'http/json'
            {'protocol' => 'http', 'encoding' => 'json'}
          else
            {'protocol' => 'http', 'encoding' => 'protobuf'}
          end
        end

        def telemetry
          Datadog.send(:components).telemetry
        end
      end
    end
  end
end
