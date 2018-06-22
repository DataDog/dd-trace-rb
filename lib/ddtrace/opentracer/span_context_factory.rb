module Datadog
  module OpenTracer
    # Creates new Datadog::OpenTracer::SpanContext
    module SpanContextFactory
      module_function

      def build(datadog_context:, baggage: {})
        SpanContext.new(
          datadog_context: datadog_context,
          baggage: baggage.dup
        )
      end

      def clone(span_context:, baggage: {})
        SpanContext.new(
          datadog_context: span_context.datadog_context,
          # Merge baggage from previous SpanContext
          baggage: span_context.baggage.merge(baggage)
        )
      end
    end
  end
end
