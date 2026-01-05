# frozen_string_literal: true

require_relative '../core/configuration/ext'

module Datadog
  module OpenTelemetry
    class Metrics
      EXPORTER_NONE = 'none'

      def self.initialize!(components)
        new(components).configure_metrics_sdk
        true
      rescue => exc
        components.logger.error("Failed to initialize OpenTelemetry metrics: #{exc.class}: #{exc}: #{exc.backtrace.join("\n")}")
        false
      end

      def initialize(components)
        @logger = components.logger
        @settings = components.settings
        @agent_host = components.agent_settings.hostname
        @agent_ssl = components.agent_settings.ssl
      end

      def configure_metrics_sdk
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

      private

      def create_resource
        resource_attributes = {}
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

        resource_attributes['service.name'] = @settings.service_without_fallback || resource_attributes['service.name'] || Datadog::Core::Environment::Ext::FALLBACK_SERVICE_NAME
        resource_attributes['deployment.environment'] = @settings.env if @settings.env
        resource_attributes['service.version'] = @settings.version if @settings.version

        ::OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
      end

      def configure_metric_reader(provider)
        exporter_name = @settings.opentelemetry.metrics.exporter
        return if exporter_name == EXPORTER_NONE

        configure_otlp_exporter(provider)
      rescue => e
        @logger.warn("Failed to configure OTLP metrics exporter:  #{e.class}: #{e}")
      end

      def default_metrics_endpoint
        "#{@agent_ssl ? "https" : "http"}://#{@agent_host}:4318/v1/metrics"
      end

      def configure_otlp_exporter(provider)
        require 'opentelemetry/exporter/otlp_metrics'
        require_relative 'sdk/metrics_exporter'

        metrics_config = @settings.opentelemetry.metrics
        endpoint = get_metrics_config_with_fallback(
          option_name: :endpoint,
          computed_default: default_metrics_endpoint
        )
        timeout = get_metrics_config_with_fallback(option_name: :timeout_millis)
        headers = get_metrics_config_with_fallback(option_name: :headers)
        # OpenTelemetry SDK only supports http/protobuf protocol.
        # TODO: Add support for http/json and grpc.
        # protocol = get_metrics_config_with_fallback(option_name: :protocol)
        exporter = Datadog::OpenTelemetry::SDK::MetricsExporter.new(
          endpoint: endpoint,
          timeout: timeout / 1000.0,
          headers: headers
        )

        reader = ::OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
          exporter: exporter,
          export_interval_millis: metrics_config.export_interval_millis,
          export_timeout_millis: metrics_config.export_timeout_millis
        )
        provider.add_metric_reader(reader)
      rescue LoadError => e
        @logger.warn("Could not load OTLP metrics exporter:  #{e.class}: #{e}")
      end

      # Returns metrics config value if explicitly set, otherwise falls back to exporter config or computed default value.
      def get_metrics_config_with_fallback(option_name:, computed_default: nil)
        if @settings.opentelemetry.metrics.using_default?(option_name)
          @settings.opentelemetry.exporter.public_send(option_name) || computed_default
        else
          @settings.opentelemetry.metrics.public_send(option_name)
        end
      end
    end
  end
end
