# typed: true
require 'datadog/tracing/context'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/propagation/http'
require 'datadog/tracing/trace_operation'
require 'datadog/opentracer/propagator'

module Datadog
  module OpenTracer
    # OpenTracing propagator for Datadog::OpenTracer::Tracer
    module RackPropagator
      extend Propagator
      extend Tracing::Distributed::Headers::Ext
      include Tracing::Distributed::Headers::Ext

      BAGGAGE_PREFIX = 'ot-baggage-'.freeze
      BAGGAGE_PREFIX_FORMATTED = 'HTTP_OT_BAGGAGE_'.freeze

      class << self
        # Inject a SpanContext into the given carrier
        #
        # @param span_context [SpanContext]
        # @param carrier [Carrier] A carrier object of Rack type
        def inject(span_context, carrier)
          active_trace = span_context.datadog_context.active_trace

          # Inject Datadog trace properties
          Tracing::Propagation::HTTP.inject!(active_trace, carrier)

          # Inject baggage
          span_context.baggage.each do |key, value|
            carrier[BAGGAGE_PREFIX + key] = value
          end

          nil
        end

        # Extract a SpanContext in Rack format from the given carrier.
        #
        # @param carrier [Carrier] A carrier object of Rack type
        # @return [SpanContext, nil] the extracted SpanContext or nil if none could be found
        def extract(carrier)
          # First extract & build a Datadog context
          datadog_trace_digest = Tracing::Propagation::HTTP.extract(carrier)

          # Then extract any other baggage
          baggage = {}
          carrier.each do |key, value|
            baggage[header_to_baggage(key)] = value if baggage_header?(key)
          end

          SpanContextFactory.build(
            datadog_context: nil,
            datadog_trace_digest: datadog_trace_digest,
            baggage: baggage
          )
        end

        private

        def baggage_header?(header)
          header.to_s.start_with?(BAGGAGE_PREFIX_FORMATTED)
        end

        def header_to_baggage(key)
          key[BAGGAGE_PREFIX_FORMATTED.length, key.length].downcase
        end
      end
    end
  end
end
