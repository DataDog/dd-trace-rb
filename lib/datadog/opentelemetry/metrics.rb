# frozen_string_literal: true

module Datadog
  module OpenTelemetry
    module Metrics
      module Initializer
        module_function

        def initialize!(settings)
          return false unless settings.opentelemetry.metrics.enabled

          unless defined?(::OpenTelemetry::SDK)
            Datadog.logger.warn('OpenTelemetry metrics requested but opentelemetry-sdk gem is not available')
            return false
          end

          unless defined?(::OpenTelemetry::SDK::Metrics)
            Datadog.logger.warn('OpenTelemetry metrics requested but opentelemetry-metrics-sdk gem is not available')
            return false
          end

          configure_metrics_sdk(settings)
          true
        rescue StandardError => e
          Datadog.logger.error("Failed to initialize OpenTelemetry metrics: #{e.message}")
          Datadog.logger.debug(e.backtrace.join("\n")) if Datadog.configuration.diagnostics.debug
          false
        end


        private

        module_function

        def configure_metrics_sdk(settings)
          require 'opentelemetry/sdk'
          require 'opentelemetry-metrics-sdk'

          current_provider = ::OpenTelemetry.meter_provider
          if current_provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
            current_provider.shutdown
          end

          resource = create_resource(settings)
          provider = ::OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: resource)
          configure_metric_reader(provider, settings)
          ::OpenTelemetry.meter_provider = provider
        end

        def create_resource(settings)
          resource_attributes = {'host.name' => Datadog::Core::Environment::Socket.hostname}

          settings.tags&.each do |key, value|
            otel_key = case key
            when 'service' then 'service.name'
            when 'env' then 'deployment.environment'
            when 'version' then 'service.version'
            else key
            end
            resource_attributes[otel_key] = value
          end

          resource_attributes['service.name'] = settings.service if settings.service
          resource_attributes['deployment.environment'] = settings.env if settings.env
          resource_attributes['service.version'] = settings.version if settings.version

          ::OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
        end

        def configure_metric_reader(provider, settings)
          exporter_name = settings.opentelemetry.metrics.exporter
          return if exporter_name == 'none'

          configure_otlp_exporter(provider, settings)
        rescue StandardError => e
          Datadog.logger.warn("Failed to configure OTLP metrics exporter: #{e.message}")
        end

        def resolve_metrics_endpoint(metrics_config, exporter_config)
          if metrics_config.endpoint
            return metrics_config.endpoint
          end

          if exporter_config.protocol == 'grpc'
            return exporter_config.endpoint
          end

          "#{exporter_config.endpoint}/v1/metrics"
        end

        def configure_otlp_exporter(provider, settings)
          require 'opentelemetry/exporter/otlp_metrics'

          metrics_config = settings.opentelemetry.metrics
          exporter_config = settings.opentelemetry.exporter
          endpoint = resolve_metrics_endpoint(metrics_config, exporter_config)
          timeout = metrics_config.timeout || exporter_config.timeout
          headers = metrics_config.headers || exporter_config.headers

          exporter = ::OpenTelemetry::Exporter::OTLP::Metrics::MetricsExporter.new(
            endpoint: endpoint,
            timeout: timeout / 1000.0,
            headers: headers
          )

          reader = ::OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
            exporter: exporter,
            export_interval_millis: metrics_config.export_interval,
            export_timeout_millis: metrics_config.export_timeout
          )
          provider.add_metric_reader(reader)
        rescue LoadError => e
          Datadog.logger.warn("Could not load OTLP metrics exporter: #{e.message}")
        end
      end
    end
  end
end

