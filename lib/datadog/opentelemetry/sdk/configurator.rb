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

        def metrics_configuration_hook
          components = Datadog.send(:components)
          return super unless components.settings.opentelemetry.metrics.enabled

          begin
            require 'opentelemetry-metrics-sdk'
          rescue LoadError => exc
            components.logger.warn("Failed to load OpenTelemetry metrics gems: #{exc.class}: #{exc}")
            return super
          end

          success = Datadog::OpenTelemetry::Metrics.initialize!(components)
          super unless success
        end

        # Prepend to ConfiguratorPatch (not Configurator) so our hook runs first.
        begin
          require 'opentelemetry-metrics-sdk' if defined?(OpenTelemetry::SDK) && !defined?(OpenTelemetry::SDK::Metrics::ConfiguratorPatch)
        rescue LoadError
        end

        if defined?(::OpenTelemetry::SDK::Metrics::ConfiguratorPatch)
          ::OpenTelemetry::SDK::Metrics::ConfiguratorPatch.prepend(self) unless ::OpenTelemetry::SDK::Metrics::ConfiguratorPatch.ancestors.include?(self)
        end
        ::OpenTelemetry::SDK::Configurator.prepend(self) unless ::OpenTelemetry::SDK::Configurator.ancestors.include?(self)
      end
    end
  end
end
