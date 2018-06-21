module Datadog
  module OpenTracer
    # Creates new Datadog::OpenTracer::SpanContext
    module SpanContextFactory
      module_function

      def build(span_id:, trace_id:, parent_id:, baggage: {})
        SpanContext.new(
          span_id: span_id,
          trace_id: trace_id,
          parent_id: parent_id,
          baggage: baggage.dup
        )
      end

      def clone(span_context:, span_id: nil, trace_id: nil, parent_id: nil, baggage: {})
        SpanContext.new(
          span_id: span_id || span_context.span_id,
          trace_id: trace_id || span_context.trace_id,
          parent_id: parent_id || span_context.parent_id,
          # Merge baggage from previous SpanContext
          baggage: span_context.baggage.merge(baggage)
        )
      end
    end
  end
end
