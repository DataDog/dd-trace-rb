# frozen_string_literal: true

require_relative "ext"
require_relative "signal_configuration"

module Datadog
  module OpenTelemetry
    class Logs
      include SignalConfiguration

      def self.initialize!(components)
        new(components).configure_logs_sdk
        true
      rescue => exc
        components.logger.warn(
          "Failed to initialize OpenTelemetry logs: #{exc.class}: #{exc.message}\n#{(exc.backtrace || []).join("\n")}",
        )
        false
      end

      def initialize(components)
        @logger = components.logger
        @settings = components.settings
        @agent_host = components.agent_settings.hostname
        @agent_ssl = components.agent_settings.ssl
      end

      def configure_logs_sdk
        provider = ::OpenTelemetry.logger_provider
        provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Logs::LoggerProvider)

        resource = create_resource
        provider = ::OpenTelemetry::SDK::Logs::LoggerProvider.new(resource: resource)
        processor_configured = configure_log_record_processor(provider)
        ::OpenTelemetry.logger_provider = provider

        disable_log_injection if processor_configured
      end

      private

      def disable_log_injection
        @logger.warn("OTel logs enabled: disabling Datadog log injection to prevent duplicate trace correlation fields")
        Datadog.configure do |c|
          c.tracing.log_injection = false # steep:ignore
        end
      end

      def configure_log_record_processor(provider)
        exporter_name = @settings.opentelemetry.logs.exporter
        return false if exporter_name == Ext::EXPORTER_NONE

        configure_otlp_exporter(provider)
      rescue => e
        @logger.warn("Failed to configure OTLP logs exporter: #{e.class}: #{e.message}")
        false
      end

      def default_logs_endpoint
        "#{@agent_ssl ? "https" : "http"}://#{@agent_host}:4318/v1/logs"
      end

      def configure_otlp_exporter(provider)
        require_relative "sdk/logs_exporter"

        logs_config = @settings.opentelemetry.logs
        endpoint = config_or_exporter_fallback(
          signal: :logs,
          option_name: :endpoint,
          computed_default: default_logs_endpoint,
        )
        timeout = config_or_exporter_fallback(signal: :logs, option_name: :timeout_millis)
        headers = config_or_exporter_fallback(signal: :logs, option_name: :headers)
        # opentelemetry-logs-sdk only supports http/protobuf protocol as of 0.5.0.
        config_or_exporter_fallback(signal: :logs, option_name: :protocol)

        exporter = Datadog::OpenTelemetry::SDK::LogsExporter.new(
          endpoint: endpoint,
          timeout: timeout / 1000.0,
          headers: headers,
        )

        processor = ::OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
          exporter,
          max_queue_size: logs_config.max_queue_size,
          schedule_delay: logs_config.schedule_delay_millis,
          exporter_timeout: logs_config.export_timeout_millis,
          max_export_batch_size: logs_config.max_export_batch_size,
        )
        provider.add_log_record_processor(processor)
        true
      rescue LoadError => e
        @logger.warn("Could not load OTLP logs exporter: #{e.class}: #{e.message}")
        false
      end
    end
  end
end
