module Datadog
  module OpenTracer
    # OpenTracing adapter for SpanContext
    class SpanContext < ::OpenTracing::SpanContext
      attr_reader \
        :span_id,
        :trace_id,
        :parent_id

      def initialize(span_id:, trace_id:, parent_id:, baggage: {})
        super(baggage: baggage)
        @span_id = span_id
        @trace_id = trace_id
        @parent_id = parent_id
        @baggage = baggage.freeze
      end
    end
  end
end
