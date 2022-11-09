# typed: false

require_relative '../configuration/ext'
require_relative '../trace_digest'
require_relative '../trace_operation'

module Datadog
  module Tracing
    module Distributed
      # Propagation::HTTP helps extracting and injecting HTTP headers.
      class Propagation
        # DEV: This class should receive the value for
        # DEV: `Datadog.configuration.tracing.distributed_tracing.propagation_inject_style`
        # DEV: at initialization time, instead of constantly reading global values.
        # DEV: This means this class should be reconfigured on `Datadog.configure` calls.
        #
        # @param propagation_styles [Hash<String,Object>]
        def initialize(propagation_styles:)
          @propagation_styles = propagation_styles
        end

        # inject! populates the env with span ID, trace ID and sampling priority
        #
        # DEV-2.0: inject! should work without arguments, injecting the active_trace's digest
        # DEV-2.0: and returning a new Hash with the injected headers.
        # DEV-2.0: inject! should also accept either a `trace` or a `digest`, as a `trace`
        # DEV-2.0: argument is the common use case, but also allows us to set error tags in the `trace`
        # DEV-2.0: if needed.
        # DEV-2.0: Ideally, we'd have a separate stream to report tracer errors and never
        # DEV-2.0: touch the active span.
        #
        # @param digest [TraceDigest]
        # @param data [Hash]
        def inject!(digest, data)
          # Prevent propagation from being attempted if trace headers provided are nil.
          if digest.nil?
            ::Datadog.logger.debug(
              'Cannot inject trace headers into data to propagate over HTTP: trace headers are nil.'.freeze
            )
            return
          end

          digest = digest.to_digest if digest.is_a?(TraceOperation)

          # Inject all configured propagation styles
          ::Datadog.configuration.tracing.distributed_tracing.propagation_inject_style.each do |style|
            propagator = @propagation_styles[style]
            begin
              propagator.inject!(digest, data) unless propagator.nil?
            rescue => e
              ::Datadog.logger.error(
                'Error injecting propagated trace headers into the environment. ' \
              "Cause: #{e} Location: #{Array(e.backtrace).first}"
              )
            end
          end
        end

        # extract returns trace headers containing the span ID, trace ID and
        # sampling priority defined in data.
        # @param data [Hash]
        def extract(data)
          trace_digest = nil
          dd_trace_digest = nil

          ::Datadog.configuration.tracing.distributed_tracing.propagation_extract_style.each do |style|
            propagator = @propagation_styles[style]
            next if propagator.nil?

            # Extract trace headers
            # DEV: `propagator.extract` will return `nil`, where `Propagation::HTTP#extract` will not
            begin
              extracted_trace_digest = propagator.extract(data)
            rescue => e
              ::Datadog.logger.error(
                'Error extracting propagated trace headers from the environment. ' \
              "Cause: #{e} Location: #{Array(e.backtrace).first}"
              )
            end

            # Skip this style if no valid headers were found
            next if extracted_trace_digest.nil?

            # Keep track of the Datadog extract trace headers, we want to return
            #   this one if we have one
            if extracted_trace_digest && style == Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG
              dd_trace_digest = extracted_trace_digest
            end

            # No previously extracted trace headers, use the one we just extracted
            if trace_digest.nil?
              trace_digest = extracted_trace_digest
            else
              unless trace_digest.trace_id == extracted_trace_digest.trace_id \
                    && trace_digest.span_id == extracted_trace_digest.span_id
                # Return an empty/new trace headers if we have a mismatch in values extracted
                msg = "#{trace_digest.trace_id} != #{extracted_trace_digest.trace_id} && " \
                    "#{trace_digest.span_id} != #{extracted_trace_digest.span_id}"
                ::Datadog.logger.debug(
                  "Cannot extract trace headers from HTTP: extracted trace headers differ, #{msg}"
                )
                # DEV: This will return from `self.extract` not this `each` block
                return TraceDigest.new
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
  end
end
