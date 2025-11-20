# frozen_string_literal: true

require_relative 'span_processor'
require_relative 'id_generator'
require_relative 'propagator'

module Datadog
  module OpenTelemetry
    module SDK
      # The Configurator is responsible for setting wiring up
      # different OpenTelemetry requirements together.
      # Some of the requirements will be changed to Datadog versions.
      module Configurator
        def initialize
          super
          @id_generator = IdGenerator
        end

        # Ensure Datadog-configure propagation styles have are applied when configured.
        #
        # DEV: Support configuring propagation through the environment variable
        # DEV: `OTEL_PROPAGATORS`, alias to `DD_TRACE_PROPAGATION_STYLE`
        def configure_propagation
          @propagators = [Propagator.new(Tracing::Contrib::HTTP)]
          super
        end

        # Ensure Datadog-configure trace writer is configured.
        def wrapped_exporters_from_env
          [SpanProcessor.new]
        end

        # Prevents default SDK metrics initialization when Datadog has already configured metrics.
        # Checks for Datadog's MetricsExporter to distinguish from SDK's default configuration.
        def metrics_configuration_hook
          current_provider = ::OpenTelemetry.meter_provider
          # Skip SDK default initialization if Datadog has already configured a MeterProvider
          if current_provider.is_a?(::OpenTelemetry::SDK::Metrics::MeterProvider)
            # Check if any reader uses Datadog's MetricsExporter
            datadog_exporter_exists = current_provider.metric_readers.any? do |reader|
              reader.instance_variable_get(:@exporter).is_a?(Datadog::OpenTelemetry::SDK::MetricsExporter)
            rescue
              false
            end
            return if datadog_exporter_exists
          end
          super
        end
        ::OpenTelemetry::SDK::Configurator.prepend(self)
      end
    end
  end
end
