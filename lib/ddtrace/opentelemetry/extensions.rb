# typed: true
require 'datadog/tracing/span_operation'
require 'ddtrace/opentelemetry/span'

module Datadog
  module OpenTelemetry
    # Defines extensions to ddtrace for OpenTelemetry support
    module Extensions
      def self.extended(base)
        Datadog::Tracing::SpanOperation.prepend(OpenTelemetry::Span)
      end
    end
  end
end
