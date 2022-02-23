# typed: true
require 'datadog/tracing/span_operation'
require 'datadog/opentelemetry/span'

# Datadog
module Datadog
  # Defines OpenTelemetry behavior
  module OpenTelemetry
    # Defines extensions to ddtrace for OpenTelemetry support
    module Extensions
      def self.extended(base)
        Datadog::Tracing::SpanOperation.prepend(OpenTelemetry::Span)
      end
    end
  end

  # Load and extend OpenTelemetry compatibility by default
  extend OpenTelemetry::Extensions
end
