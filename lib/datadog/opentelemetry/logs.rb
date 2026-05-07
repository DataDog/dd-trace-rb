# frozen_string_literal: true

require_relative '../core/configuration/ext'

module Datadog
  module OpenTelemetry
    class Logs
      EXPORTER_NONE = 'none'

      def self.initialize!(components)
        new(components).configure_logs_sdk
        true
      rescue => exc
        components.logger.error("Failed to initialize OpenTelemetry logs: #{exc.class}: #{exc}: #{exc.backtrace.join("\n")}")
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
        configure_log_record_processor(provider)
        ::OpenTelemetry.logger_provider = provider

        # FR09: disable Datadog log injection to avoid duplicate trace correlation fields
        Datadog.configure do |c|
          c.tracing.log_injection = false
        end
      end

      private

      def create_resource
        resource_attributes = {}

        @settings.tags&.each do |key, value|
          otel_key = case key
          when 'service' then 'service.name'
          when 'env' then 'deployment.environment'
          when 'version' then 'service.version'
          else key
          end
          resource_attributes[otel_key] = value
        end

        resource_attributes['service.name'] = @settings.service_without_fallback || resource_attributes['service.name'] || Datadog::Core::Environment::Ext::FALLBACK_SERVICE_NAME
        resource_attributes['deployment.environment'] = @settings.env if @settings.env
        resource_attributes['service.version'] = @settings.version if @settings.version

        if @settings.tracing.report_hostname
          if @settings.hostname
            resource_attributes['host.name'] = @settings.hostname
          else
            resource_attributes['host.name'] ||= Datadog::Core::Environment::Socket.hostname
          end
        end

        ::OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
      end

      def configure_log_record_processor(provider)
        exporter_name = @settings.opentelemetry.logs.exporter
        return if exporter_name == EXPORTER_NONE

        configure_otlp_exporter(provider)
      rescue => e
        @logger.warn("Failed to configure OTLP logs exporter: #{e.class}: #{e}")
      end

      def default_logs_endpoint(protocol)
        if protocol == 'grpc'
          "#{@agent_ssl ? 'https' : 'http'}://#{@agent_host}:4317"
        else
          "#{@agent_ssl ? 'https' : 'http'}://#{@agent_host}:4318/v1/logs"
        end
      end

      def configure_otlp_exporter(provider)
        require 'opentelemetry/exporter/otlp_logs'
        require_relative 'sdk/logs_exporter'

        logs_config = @settings.opentelemetry.logs
        protocol = get_logs_config_with_fallback(option_name: :protocol)
        endpoint = get_logs_config_with_fallback(
          option_name: :endpoint,
          computed_default: default_logs_endpoint(protocol)
        )
        timeout = get_logs_config_with_fallback(option_name: :timeout_millis) || 10_000
        headers = get_logs_config_with_fallback(option_name: :headers)

        exporter = Datadog::OpenTelemetry::SDK::LogsExporter.new(
          protocol: protocol,
          endpoint: endpoint,
          timeout: timeout / 1000.0,
          headers: headers
        )

        processor = ::OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(
          exporter,
          max_queue_size: logs_config.max_queue_size,
          schedule_delay: logs_config.schedule_delay_millis,
          exporter_timeout: logs_config.export_timeout_millis,
          max_export_batch_size: logs_config.max_export_batch_size
        )
        provider.add_log_record_processor(processor)
      rescue LoadError => e
        @logger.warn("Could not load OTLP logs exporter: #{e.class}: #{e}")
      end

      # Returns logs config value if explicitly set, otherwise falls back to exporter config or computed default value.
      def get_logs_config_with_fallback(option_name:, computed_default: nil)
        if @settings.opentelemetry.logs.using_default?(option_name)
          @settings.opentelemetry.exporter.public_send(option_name) || computed_default
        else
          @settings.opentelemetry.logs.public_send(option_name)
        end
      end
    end
  end
end
