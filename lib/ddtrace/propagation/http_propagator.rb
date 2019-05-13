require 'ddtrace/configuration'
require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/priority'
require 'ddtrace/propagation/distributed_headers/b3'
require 'ddtrace/propagation/distributed_headers/b3_single'
require 'ddtrace/propagation/distributed_headers/datadog'

module Datadog
  # HTTPPropagator helps extracting and injecting HTTP headers.
  module HTTPPropagator
    include Ext::DistributedTracing

    PROPAGATION_STYLES = { PROPAGATION_STYLE_B3 => DistributedHeaders::B3,
                           PROPAGATION_STYLE_B3_SINGLE_HEADER => DistributedHeaders::B3Single,
                           PROPAGATION_STYLE_DATADOG => DistributedHeaders::Datadog }

    # inject! popolates the env with span ID, trace ID and sampling priority
    def self.inject!(context, env)
      # Prevent propagation from being attempted if context provided is nil.
      if context.nil?
        ::Datadog::Tracer.log.debug('Cannot inject context into env to propagate over HTTP: context is nil.'.freeze)
        return
      end

      # Inject all configured propagation styles
      ::Datadog.configuration.propagation_inject_style.each do |style|
        propagator = PROPAGATION_STYLES[style]
        propagator.inject!(context, env) unless propagator.nil?
      end
    end

    # extract returns a context containing the span ID, trace ID and
    # sampling priority defined in env.
    def self.extract(env)
      context = nil
      dd_context = nil

      ::Datadog.configuration.propagation_extract_style.each do |style|
        propagator = PROPAGATION_STYLES[style]
        next if propagator.nil?

        # Extract context
        # DEV: `propagator.extract` will return `nil`, where `HTTPPropagator#extract` will not
        extracted_context = propagator.extract(env)
        # Skip this style if no valid headers were found
        next if extracted_context.nil?

        # Keep track of the Datadog extract context, we want to return
        #   this one if we have one
        dd_context = extracted_context if extracted_context and style == PROPAGATION_STYLE_DATADOG

        # No previously extracted context, use the one we just extracted
        if context.nil?
          context = extracted_context
        else
          # Return an empty/new context if we have a mismatch in values extracted
          # DEV: This will return from `self.extract` not this `each` block
          msg = "#{context.trace_id} != #{extracted_context.trace_id} && #{context.span_id} != #{extracted_context.span_id}"
          ::Datadog::Tracer.log.debug("Cannot extract context from HTTP: extracted contexts differ, #{msg}".freeze)
          return ::Datadog::Context.new unless context.trace_id == extracted_context.trace_id && context.span_id == extracted_context.span_id
        end
      end

      # Return the extracted context if we found one or else a new empty context
      # Always return the Datadog context if one exists since it has more
      #   information than the B3 headers e.g. origin, expanded priority
      #   sampling values, etc
      dd_context || context || ::Datadog::Context.new
    end
  end
end
