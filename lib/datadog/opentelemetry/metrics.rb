# frozen_string_literal: true

require_relative '../core/configuration/ext'

module Datadog
  module OpenTelemetry
    module Metrics
      module_function

      def initialize!(settings, agent_settings, logger)
        @logger = logger
        @settings = settings
        @agent_host = if agent_settings&.hostname && !agent_settings.hostname.empty?
          agent_settings.hostname
        elsif (host = @settings.agent.host) && !host.empty?
          host
        else
          Datadog::Core::Configuration::Ext::Agent::HTTP::DEFAULT_HOST
        end
        begin
          require 'opentelemetry/sdk'
        rescue LoadError
          @logger.warn('OpenTelemetry metrics enabled but opentelemetry-sdk gem is missing. Add "gem \'opentelemetry-sdk\'" to your Gemfile.')
          return false
        end

        begin
          require 'opentelemetry-metrics-sdk'
        rescue LoadError
          @logger.warn('OpenTelemetry metrics enabled but opentelemetry-metrics-sdk gem is missing. Add "gem \'opentelemetry-metrics-sdk\'" to your Gemfile.')
          return false
        end

        configure_metrics_sdk
        true
      rescue => e
        @logger.error("Failed to initialize OpenTelemetry metrics: #{e.message}")
        @logger.debug(e.backtrace.join("\n")) if @settings.diagnostics.debug
        false
      end

      private

      module_function

      def configure_metrics_sdk
        # Require configurator which handles its own prepend
        require_relative 'sdk/configurator'

        current_provider = ::OpenTelemetry.meter_provider
        if current_provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
          current_provider.shutdown
        end

        # OpenTelemetry SDK sets default temporality preference to cumulative,
        # this is not compatible with the Datadog agent.
        if DATADOG_ENV['OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE'].nil?
          # OpenTelemetry SDK reads from ENV directly, so we must write to ENV
          ENV['OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE'] = 'delta' # rubocop:disable CustomCops/EnvUsageCop
        end

        resource = create_resource
        provider = ::OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: resource)
        configure_metric_reader(provider)
        ::OpenTelemetry.meter_provider = provider
      end

      def create_resource
        resource_attributes = {
          'service.name' => @settings.service || Datadog::Core::Environment::Ext::FALLBACK_SERVICE_NAME,
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

      def configure_metric_reader(provider)
        exporter_name = @settings.opentelemetry.metrics.exporter
        return if exporter_name == 'none'

        configure_otlp_exporter(provider)
      rescue => e
        @logger.warn("Failed to configure OTLP metrics exporter: #{e.message}")
      end

      def resolve_metrics_endpoint
        metrics_config = @settings.opentelemetry.metrics
        exporter_config = @settings.opentelemetry.exporter

        return metrics_config.endpoint if metrics_config.endpoint

        if metrics_config.protocol
          protocol = metrics_config.protocol
          port = (protocol == 'http/protobuf') ? 4318 : 4317
          path = (protocol == 'http/protobuf') ? '/v1/metrics' : ''
          return "http://#{@agent_host}:#{port}#{path}"
        end

        return exporter_config.endpoint if exporter_config.endpoint

        protocol = exporter_config.protocol || 'http/protobuf'
        port = (protocol == 'http/protobuf') ? 4318 : 4317
        path = (protocol == 'http/protobuf') ? '/v1/metrics' : ''
        "http://#{@agent_host}:#{port}#{path}"
      end

      def configure_otlp_exporter(provider)
        require 'opentelemetry/exporter/otlp_metrics'
        require_relative 'sdk/exporter'

        metrics_config = @settings.opentelemetry.metrics
        exporter_config = @settings.opentelemetry.exporter
        timeout = metrics_config.timeout || exporter_config.timeout
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
          export_interval_millis: metrics_config.export_interval,
          export_timeout_millis: metrics_config.export_timeout
        )
        provider.add_metric_reader(reader)
      rescue LoadError => e
        @logger.warn("Could not load OTLP metrics exporter: #{e.message}")
      end
    end
  end
end
