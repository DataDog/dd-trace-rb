# frozen_string_literal: true

require_relative '../configuration/ext'
require_relative '../trace_digest'
require_relative '../trace_operation'

module Datadog
  module Tracing
    module Distributed
      # Provides extraction and injection of distributed trace data.
      class Propagation
        # DEV: This class should receive the value for
        # DEV: `Datadog.configuration.tracing.distributed_tracing.propagation_inject_style`
        # DEV: at initialization time, instead of constantly reading global values.
        # DEV: This means this class should be reconfigured on `Datadog.configure` calls, thus
        # DEV: singleton instances should not used as they will become stale.
        #
        # @param propagation_styles [Hash<String,Object>]
        def initialize(propagation_styles:)
          @propagation_styles = propagation_styles
        end

        # inject! populates the env with span ID, trace ID and sampling priority
        #
        # This method will never raise errors, but instead log them to `Datadog.logger`.
        #
        # DEV-2.0: inject! should work without arguments, injecting the active_trace's digest
        # DEV-2.0: and returning a new Hash with the injected data.
        # DEV-2.0: inject! should also accept either a `trace` or a `digest`, as a `trace`
        # DEV-2.0: argument is the common use case, but also allows us to set error tags in the `trace`
        # DEV-2.0: if needed.
        # DEV-2.0: Ideally, we'd have a separate stream to report tracer errors and never
        # DEV-2.0: touch the active span.
        #
        # @param digest [TraceDigest]
        # @param data [Hash]
        # @return [Boolean] `true` if injected successfully, `false` if no propagation style is configured
        # @return [nil] in case of error, see `Datadog.logger` output for details.
        def inject!(digest, data)
          if digest.nil?
            ::Datadog.logger.debug('Cannot inject distributed trace data: digest is nil.')
            return nil
          end

          digest = digest.to_digest if digest.respond_to?(:to_digest)

          result = false

          # Inject all configured propagation styles
          ::Datadog.configuration.tracing.distributed_tracing.propagation_inject_style.each do |style|
            propagator = @propagation_styles[style]
            begin
              if propagator
                propagator.inject!(digest, data)
                result = true
              end
            rescue => e
              result = nil
              ::Datadog.logger.error(
                "Error injecting distributed trace data. Cause: #{e} Location: #{Array(e.backtrace).first}"
              )
            end
          end

          result
        end

        # extract returns {TraceDigest} containing the distributed trace information.
        # sampling priority defined in data.
        #
        # This method will never raise errors, but instead log them to `Datadog.logger`.
        #
        # @param data [Hash]
        def extract(data)
          trace_digest = nil
          dd_trace_digest = nil

          ::Datadog.configuration.tracing.distributed_tracing.propagation_extract_style.each do |style|
            propagator = @propagation_styles[style]
            next if propagator.nil?

            begin
              extracted_trace_digest = propagator.extract(data)
            rescue => e
              ::Datadog.logger.error(
                'Error extracting distributed trace data. ' \
              "Cause: #{e} Location: #{Array(e.backtrace).first}"
              )
            end

            # Skip if no valid data was found
            next if extracted_trace_digest.nil?

            # Keep track of the Datadog extracted digest, we want to return it if we have it.
            if extracted_trace_digest && style == Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG
              dd_trace_digest = extracted_trace_digest
            end

            # No previously extracted trace data, use the one we just extracted
            if trace_digest.nil?
              trace_digest = extracted_trace_digest
            else
              unless trace_digest.trace_id == extracted_trace_digest.trace_id \
                    && trace_digest.span_id == extracted_trace_digest.span_id
                # We have two mismatched propagation contexts
                ::Datadog.logger.debug do
                  'Cannot extract distributed trace data: extracted styles differ, ' \
                  "#{trace_digest.trace_id} != #{extracted_trace_digest.trace_id} && " \
                  "#{trace_digest.span_id} != #{extracted_trace_digest.span_id}"
                end

                # It's safer to create a new context than to attach ourselves to the wrong context
                return TraceDigest.new # Early return from the whole method
              end
            end
          end

          # Return the extracted trace digest if we found one or else a new empty digest.
          # Always return the Datadog trace digest if one exists since it has more
          # information than the B3 digest, e.g. origin, priority sampling values.
          dd_trace_digest || trace_digest || nil
        end
      end
    end
  end
end
