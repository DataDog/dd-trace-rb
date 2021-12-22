# typed: true
module Datadog
  module OpenTracer
    # OpenTracing adapter for SpanContext
    # @public_api
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
