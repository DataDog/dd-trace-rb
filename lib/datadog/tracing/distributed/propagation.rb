# frozen_string_literal: true

require_relative '../configuration/ext'
require_relative '../trace_digest'
require_relative '../trace_operation'

module Datadog
  module Tracing
    module Distributed
      # Provides extraction and injection of distributed trace data.
      class Propagation
        # @param propagation_styles [Hash<String,Object>]
        #  a map of propagation styles to their corresponding implementations
        # @param propagation_style_inject [Array<String>]
        #   a list of styles to use when injecting distributed trace data
        # @param propagation_style_extract [Array<String>]
        #   a list of styles to use when extracting distributed trace data
        # @param propagation_extract_first [Boolean]
        #   if true, only the first successfully extracted trace will be used
        def initialize(
          propagation_styles:,
          propagation_style_inject:,
          propagation_style_extract:,
          propagation_extract_first:
        )
          @propagation_styles = propagation_styles
          @propagation_extract_first = propagation_extract_first

          @propagation_style_inject = propagation_style_inject.map { |style| propagation_styles[style] }
          @propagation_style_extract = propagation_style_extract.map { |style| propagation_styles[style] }
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
          @propagation_style_inject.each do |propagator|
            propagator.inject!(digest, data)
            result = true
          rescue => e
            result = nil
            ::Datadog.logger.error(
              "Error injecting distributed trace data. Cause: #{e} Location: #{Array(e.backtrace).first}"
            )
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
          return unless data
          return if data.empty?

          extracted_trace_digest = nil

          @propagation_style_extract.each do |propagator|
            # First extraction?
            unless extracted_trace_digest
              extracted_trace_digest = propagator.extract(data)
              next
            end

            # Return if we are only inspecting the first valid style.
            next if @propagation_extract_first

            # Continue parsing styles to find the W3C `tracestate` header, if present.
            # `tracestate` must always be propagated, as it might contain pass-through data that we don't control.
            # @see https://www.w3.org/TR/2021/REC-trace-context-1-20211123/#mutating-the-tracestate-field
            next unless propagator.is_a?(TraceContext)

            if (tracecontext_digest = propagator.extract(data))
              # Only parse if it represent the same trace as the successfully extracted one
              next unless tracecontext_digest.trace_id == extracted_trace_digest.trace_id

              # Preserve the `tracestate`
              extracted_trace_digest = extracted_trace_digest.merge(
                trace_state: tracecontext_digest.trace_state,
                trace_state_unknown_fields: tracecontext_digest.trace_state_unknown_fields
              )
            end
          rescue => e
            ::Datadog.logger.error(
              "Error extracting distributed trace data. Cause: #{e} Location: #{Array(e.backtrace).first}"
            )
          end

          extracted_trace_digest
        end
      end
    end
  end
end
