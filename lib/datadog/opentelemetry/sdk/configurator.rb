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

        # Override metrics_configuration_hook to use Datadog's metrics initialization
        def metrics_configuration_hook
          require_relative '../../metrics' if defined?(OpenTelemetry::SDK::Metrics)
          return super unless defined?(Datadog::OpenTelemetry::Metrics::Initializer)
          # Only initialize if metrics are enabled, otherwise let default SDK handle it
          return super unless Datadog.configuration.opentelemetry.metrics.enabled

          Datadog::OpenTelemetry::Metrics::Initializer.initialize!(Datadog.configuration)
        end

        ::OpenTelemetry::SDK::Configurator.prepend(self)
      end
    end
  end
end
