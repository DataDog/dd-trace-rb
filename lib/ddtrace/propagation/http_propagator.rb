# typed: false
require 'ddtrace/configuration'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/priority'
require 'ddtrace/distributed_tracing/headers/b3'
require 'ddtrace/distributed_tracing/headers/b3_single'
require 'ddtrace/distributed_tracing/headers/datadog'
require 'ddtrace/trace_digest'

module Datadog
  # HTTPPropagator helps extracting and injecting HTTP headers.
  # @public_api
  module HTTPPropagator
    include Ext::DistributedTracing

    PROPAGATION_STYLES = { PROPAGATION_STYLE_B3 => DistributedTracing::Headers::B3,
                           PROPAGATION_STYLE_B3_SINGLE_HEADER => DistributedTracing::Headers::B3Single,
                           PROPAGATION_STYLE_DATADOG => DistributedTracing::Headers::Datadog }.freeze

    # inject! popolates the env with span ID, trace ID and sampling priority
    def self.inject!(digest, env)
      # Prevent propagation from being attempted if trace headers provided are nil.
      if digest.nil?
        ::Datadog.logger.debug('Cannot inject trace headers into env to propagate over HTTP: trace headers are nil.'.freeze)
        return
      end

      digest = digest.to_digest if digest.is_a?(TraceOperation)

      # Inject all configured propagation styles
      ::Datadog::Tracing.configuration.distributed_tracing.propagation_inject_style.each do |style|
        propagator = PROPAGATION_STYLES[style]
        begin
          propagator.inject!(digest, env) unless propagator.nil?
        rescue => e
          Datadog.logger.error(
            'Error injecting propagated trace headers into the environment. ' \
            "Cause: #{e} Location: #{Array(e.backtrace).first}"
          )
        end
      end
    end

    # extract returns trace headers containing the span ID, trace ID and
    # sampling priority defined in env.
    def self.extract(env)
      trace_digest = nil
      dd_trace_digest = nil

      ::Datadog::Tracing.configuration.distributed_tracing.propagation_extract_style.each do |style|
        propagator = PROPAGATION_STYLES[style]
        next if propagator.nil?

        # Extract trace headers
        # DEV: `propagator.extract` will return `nil`, where `HTTPPropagator#extract` will not
        begin
          extracted_trace_digest = propagator.extract(env)
        rescue => e
          Datadog.logger.error(
            'Error extracting propagated trace headers from the environment. ' \
            "Cause: #{e} Location: #{Array(e.backtrace).first}"
          )
        end

        # Skip this style if no valid headers were found
        next if extracted_trace_digest.nil?

        # Keep track of the Datadog extract trace headers, we want to return
        #   this one if we have one
        dd_trace_digest = extracted_trace_digest if extracted_trace_digest && style == PROPAGATION_STYLE_DATADOG

        # No previously extracted trace headers, use the one we just extracted
        if trace_digest.nil?
          trace_digest = extracted_trace_digest
        else
          unless trace_digest.trace_id == extracted_trace_digest.trace_id \
                   && trace_digest.span_id == extracted_trace_digest.span_id
            # Return an empty/new trace headers if we have a mismatch in values extracted
            msg = "#{trace_digest.trace_id} != #{extracted_trace_digest.trace_id} && " \
                  "#{trace_digest.span_id} != #{extracted_trace_digest.span_id}"
            ::Datadog.logger.debug("Cannot extract trace headers from HTTP: extracted trace headers differ, #{msg}".freeze)
            # DEV: This will return from `self.extract` not this `each` block
            return ::Datadog::TraceDigest.new
          end
        end
      end

      # Return the extracted trace headers if we found one or else a new empty trace headers
      # Always return the Datadog trace headers if one exists since it has more
      #   information than the B3 headers e.g. origin, expanded priority
      #   sampling values, etc
      dd_trace_digest || trace_digest || nil
    end
  end
end
