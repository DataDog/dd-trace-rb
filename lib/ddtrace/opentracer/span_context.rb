module Datadog
  module OpenTracer
    # OpenTracing adapter for SpanContext
    class SpanContext < ::OpenTracing::SpanContext
      attr_reader \
        :datadog_context

      def initialize(datadog_context:, baggage: {})
        @datadog_context = datadog_context
        @baggage = baggage.freeze
      end
    end
  end
end
