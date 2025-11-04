# frozen_string_literal: true

module Datadog
  module OpenTelemetry
    module MetricsConfiguration
      def configure(&block)
        result = super
        Datadog::OpenTelemetry::Metrics::Initializer.initialize!(self.configuration) if defined?(Datadog::OpenTelemetry::Metrics::Initializer)
        result
      end
    end
  end
end

if defined?(::OpenTelemetry::SDK) && defined?(::OpenTelemetry::SDK::Metrics)
  Datadog.singleton_class.prepend(Datadog::OpenTelemetry::MetricsConfiguration) unless Datadog.singleton_class.ancestors.include?(Datadog::OpenTelemetry::MetricsConfiguration)
end

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

          metrics_config = settings.opentelemetry.metrics
          exporter_config = settings.opentelemetry.exporter
          resource = create_resource(settings)

          current_provider = ::OpenTelemetry.meter_provider
          current_provider.shutdown if current_provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)

          provider = ::OpenTelemetry::SDK::Metrics::MeterProvider.new(resource: resource)
          configure_metric_reader(provider, metrics_config, exporter_config)
          ::OpenTelemetry.meter_provider = provider
        end

        def create_resource(settings)
          resource_attributes = {}
          resource_attributes['service.name'] = settings.service if settings.service
          resource_attributes['deployment.environment'] = settings.env if settings.env
          resource_attributes['service.version'] = settings.version if settings.version

          settings.tags&.each do |key, value|
            otel_key = case key
            when 'service' then 'service.name'
            when 'env' then 'deployment.environment'
            when 'version' then 'service.version'
            else key
            end
            resource_attributes[otel_key] = value unless resource_attributes.key?(otel_key)
          end

          ::OpenTelemetry::SDK::Resources::Resource.create(resource_attributes)
        end

        def configure_metric_reader(provider, metrics_config, exporter_config)
          exporter_name = metrics_config.exporter
          return if exporter_name == 'none'

          endpoint = resolve_metrics_endpoint(metrics_config, exporter_config)
          configure_console_exporter(provider, metrics_config, endpoint)
        rescue StandardError
          exporter_name = metrics_config.exporter
          Datadog.logger.warn("Unknown OpenTelemetry metrics exporter '#{exporter_name}', using console exporter") unless exporter_name == 'none'
          configure_console_exporter(provider, metrics_config, nil)
        end

        def resolve_metrics_endpoint(metrics_config, exporter_config)
          metrics_endpoint = metrics_config.endpoint
          metrics_protocol = ENV['OTEL_EXPORTER_OTLP_METRICS_PROTOCOL']
          
          return metrics_endpoint if metrics_endpoint || metrics_protocol

          exporter_endpoint = exporter_config.endpoint
          return nil unless exporter_endpoint

          protocol = ENV['OTEL_EXPORTER_OTLP_PROTOCOL'] || 'grpc'
          return exporter_endpoint unless protocol == 'http/protobuf' || protocol == 'http/json'

          exporter_endpoint.end_with?('/v1/metrics') ? exporter_endpoint : "#{exporter_endpoint}/v1/metrics"
        end

        def configure_console_exporter(provider, metrics_config, endpoint)
          require 'opentelemetry/sdk/metrics/export/console_metric_pull_exporter'
          exporter = ::OpenTelemetry::SDK::Metrics::Export::ConsoleMetricPullExporter.new
          reader = ::OpenTelemetry::SDK::Metrics::Export::PeriodicMetricReader.new(
            exporter: exporter,
            export_interval_millis: metrics_config.export_interval || 60_000,
            export_timeout_millis: metrics_config.export_timeout || 30_000
          )
          provider.add_metric_reader(reader)
        rescue LoadError => e
          Datadog.logger.warn("Could not load console metrics exporter: #{e.message}")
        end
      end
    end
  end
end

