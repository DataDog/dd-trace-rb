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

    # inject! popolates the env with span ID, trace ID and sampling priority
    def self.inject!(context, env)
      # Prevent propagation from being attempted if context provided is nil.
      if context.nil?
        ::Datadog::Tracer.log.debug('Cannot inject context into env to propagate over HTTP: context is nil.'.freeze)
        return
      end

      # Check if they want to propagate with B3 headers
      if ::Datadog.configuration.propagation_inject_style.include?(PROPAGATION_STYLE_B3)
        DistributedHeaders::B3.inject!(context, env)
      end

      # Check if they want to propagate with B3 single header
      if ::Datadog.configuration.propagation_inject_style.include?(PROPAGATION_STYLE_B3_SINGLE_HEADER)
        DistributedHeaders::B3Single.inject!(context, env)
      end

      # Check if they want to propagate with Datadog headers
      if ::Datadog.configuration.propagation_inject_style.include?(PROPAGATION_STYLE_DATADOG)
        DistributedHeaders::Datadog.inject!(context, env)
      end
    end

    # extract returns a context containing the span ID, trace ID and
    # sampling priority defined in env.
    def self.extract(env)
      context = nil
      dd_context = nil
      ::Datadog.configuration.propagation_extract_style.each do |style|
        extracted_context = nil
        case style
        when PROPAGATION_STYLE_DATADOG
          extracted_context = DistributedHeaders::Datadog.extract(env)
          # Keep track of the Datadog extract context, we want to return
          #   this one if we have one
          dd_context = extracted_context
        when PROPAGATION_STYLE_B3
          extracted_context = DistributedHeaders::B3.extract(env)
        when PROPAGATION_STYLE_B3_SINGLE_HEADER
          extracted_context = DistributedHeaders::B3Single.extract(env)
        end

        # Skip this style if no valid headers were found
        next if extracted_context.nil?

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
