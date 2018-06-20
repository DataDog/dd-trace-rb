module Datadog
  module OpenTracer
    # OpenTracing adapter for SpanContext
    class SpanContext < ::OpenTracing::SpanContext
      def initialize(baggage: {})
        super
        @baggage = baggage
      end
    end
  end
end
