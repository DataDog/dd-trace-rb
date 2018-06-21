module Datadog
  module OpenTracer
    # Creates new Datadog::OpenTracer::SpanContext
    module SpanContextFactory
      module_function

      def build(span_context: nil, baggage: {})
        # Merge baggage from previous SpanContext
        baggage = span_context.nil? ? baggage.dup : span_context.baggage.merge(baggage)

        SpanContext.new(baggage: baggage)
      end
    end
  end
end
