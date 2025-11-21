# frozen_string_literal: true

require_relative '../core/configuration/ext'

module Datadog
  module OpenTelemetry
    module Metrics
      def self.initialize!(components)
        @logger = components.logger
        @settings = components.settings
        @agent_host = components.agent_settings.hostname
        @agent_ssl = components.agent_settings.ssl

        configure_metrics_sdk
        true
      rescue => exc
        @logger.error("Failed to initialize OpenTelemetry metrics: #{exc.class}: #{exc}: #{exc.backtrace.join("\n")}")
        false
      end

      def self.configure_metrics_sdk
        provider = ::OpenTelemetry.meter_provider
        provider.shutdown if provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)

        # The OpenTelemetry SDK defaults to cumulative temporality, but Datadog prefers delta temporality.
        # Here is an example of how this config is applied: https://github.com/open-telemetry/opentelemetry-ruby/blob/1933d4c18e5f5e45c53fa9e902e58aa91e85cc38/metrics_sdk/lib/opentelemetry/sdk/metrics/aggregation/sum.rb#L14
        if DATADOG_ENV['OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE'].nil?
          ENV['OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE'] = 'delta' # rubocop:disable CustomCops/EnvUsageCop
        end

        resource = create_resource
        provider = ::OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: resource)
        configure_metric_reader(provider)
        ::OpenTelemetry.meter_provider = provider
      end

      def self.create_resource
        resource_attributes = {
          'service.name' => @settings.service || '',
          'deployment.environment' => @settings.env || '',
          'service.version' => @settings.version || '',
        }
        resource_attributes['host.name'] = Datadog::Core::Environment::Socket.hostname if @settings.tracing.report_hostname

        @settings.tags&.each do |key, value|
          otel_key = case key
          when 'service' then 'service.name'
          when 'env' then 'deployment.environment'
          when 'version' then 'service.version'
          else key
          end
          resource_attributes[otel_key] = value
        end

        ::OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
      end

      def self.configure_metric_reader(provider)
        exporter_name = @settings.opentelemetry.metrics.exporter
        return if exporter_name == 'none'

        configure_otlp_exporter(provider)
      rescue => e
        @logger.warn("Failed to configure OTLP metrics exporter: #{e.message}")
      end

      def self.resolve_metrics_endpoint
        metrics_config = @settings.opentelemetry.metrics
        exporter_config = @settings.opentelemetry.exporter

        return metrics_config.endpoint.to_s if metrics_config.endpoint
        scheme = @agent_ssl ? 'https' : 'http'

        if metrics_config.protocol
          protocol = metrics_config.protocol
          port = (protocol == 'http/protobuf') ? 4318 : 4317
          path = (protocol == 'http/protobuf') ? '/v1/metrics' : ''
          return "#{scheme}://#{@agent_host}:#{port}#{path}"
        end

        return exporter_config.endpoint.to_s if exporter_config.endpoint

        protocol = exporter_config.protocol || 'http/protobuf'
        port = (protocol == 'http/protobuf') ? 4318 : 4317
        path = (protocol == 'http/protobuf') ? '/v1/metrics' : ''
        "#{scheme}://#{@agent_host}:#{port}#{path}"
      end

      def self.configure_otlp_exporter(provider)
        require 'opentelemetry/exporter/otlp_metrics'
        require_relative 'sdk/metrics_exporter'

        metrics_config = @settings.opentelemetry.metrics
        exporter_config = @settings.opentelemetry.exporter
        timeout = metrics_config.timeout_millis || exporter_config.timeout_millis
        headers = metrics_config.headers || exporter_config.headers || {}

        protocol = metrics_config.protocol || exporter_config.protocol
        exporter = Datadog::OpenTelemetry::SDK::MetricsExporter.new(
          endpoint: resolve_metrics_endpoint,
          timeout: timeout / 1000.0,
          headers: headers,
          protocol: protocol
        )

        reader = ::OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
          exporter: exporter,
          export_interval_millis: metrics_config.export_interval_millis,
          export_timeout_millis: metrics_config.export_timeout_millis
        )
        provider.add_metric_reader(reader)
      rescue LoadError => e
        @logger.warn("Could not load OTLP metrics exporter: #{e.message}")
      end

      private_class_method :configure_metrics_sdk, :create_resource, :configure_metric_reader, :resolve_metrics_endpoint, :configure_otlp_exporter
    end
  end
end
