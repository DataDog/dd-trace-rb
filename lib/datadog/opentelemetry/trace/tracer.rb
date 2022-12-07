# frozen_string_literal: true

require 'opentelemetry/trace/tracer'

module Datadog
  module OpenTelemetry
    module Trace
      # Implements the {OpenTelemetry::Trace::Tracer}.
      class Tracer < ::OpenTelemetry::Trace::Tracer
        # @api private
        #
        # Returns a new {Tracer} instance.
        #
        # @param [String] name Instrumentation package name
        # @param [String] version Instrumentation package version
        # @param [TracerProvider] tracer_provider TracerProvider that initialized the tracer
        #
        # @return [Tracer]
        def initialize(name, version, tracer_provider)
          @instrumentation_scope = InstrumentationScope.new(name, version)
          @tracer_provider = tracer_provider
        end

        def start_root_span(name, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          start_span(name, with_parent: Context.empty, attributes: attributes, links: links, start_timestamp: start_timestamp, kind: kind)
        end

        def start_span(name, with_parent: nil, attributes: nil, links: nil, start_timestamp: nil, kind: nil)
          name ||= 'empty'
          kind ||= :internal
          with_parent ||= Context.current

          @tracer_provider.internal_start_span(name, kind, attributes, links, start_timestamp, with_parent, @instrumentation_scope)
        end
      end
    end
  end
end

