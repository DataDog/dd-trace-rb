require 'ddtrace/ext/distributed'

module Datadog
  module OpenTracer
    # OpenTracing propagator for Datadog::OpenTracer::Tracer
    module TextMapPropagator
      extend Propagator
      extend Datadog::Ext::DistributedTracing
      include Datadog::Ext::DistributedTracing

      BAGGAGE_PREFIX = 'ot-baggage-'.freeze

      class << self
        # Inject a SpanContext into the given carrier
        #
        # @param span_context [SpanContext]
        # @param carrier [Carrier] A carrier object of Rack type
        def inject(span_context, carrier)
          # Inject Datadog trace properties
          span_context.datadog_context.tap do |datadog_context|
            carrier[HTTP_HEADER_TRACE_ID] = datadog_context.trace_id
            carrier[HTTP_HEADER_PARENT_ID] = datadog_context.span_id
            carrier[HTTP_HEADER_SAMPLING_PRIORITY] = datadog_context.sampling_priority
            carrier[HTTP_HEADER_ORIGIN] = datadog_context.origin
          end

          # Inject baggage
          span_context.baggage.each do |key, value|
            carrier[BAGGAGE_PREFIX + key] = value
          end

          nil
        end

        # Extract a SpanContext in TextMap format from the given carrier.
        #
        # @param carrier [Carrier] A carrier object of TextMap type
        # @return [SpanContext, nil] the extracted SpanContext or nil if none could be found
        def extract(carrier)
          # First extract & build a Datadog context
          headers = DistributedHeaders.new(carrier)

          datadog_context = if headers.valid?
                              Datadog::Context.new(
                                trace_id: headers.trace_id,
                                span_id: headers.parent_id,
                                sampling_priority: headers.sampling_priority,
                                origin: headers.origin
                              )
                            else
                              Datadog::Context.new
                            end

          # Then extract any other baggage
          baggage = {}
          carrier.each do |key, value|
            baggage[item_to_baggage(key)] = value if baggage_item?(key)
          end

          SpanContextFactory.build(datadog_context: datadog_context, baggage: baggage)
        end

        private

        def baggage_item?(item)
          item.to_s.start_with?(BAGGAGE_PREFIX)
        end

        def item_to_baggage(key)
          key[BAGGAGE_PREFIX.length, key.length]
        end
      end
    end
  end
end
