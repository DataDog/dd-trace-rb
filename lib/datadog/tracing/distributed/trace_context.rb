# frozen_string_literal: true

require_relative "helpers"
require_relative "trace_state"

module Datadog
  module Tracing
    module Distributed
      # W3C Trace Context propagator implementation, version 00.
      # The trace is propagated through two fields: `traceparent` and `tracestate`.
      # @see https://www.w3.org/TR/trace-context/
      class TraceContext
        TRACEPARENT_KEY = "traceparent"
        TRACESTATE_KEY = "tracestate"
        SPEC_VERSION = "00"

        def initialize(
          fetcher:,
          traceparent_key: TRACEPARENT_KEY,
          tracestate_key: TRACESTATE_KEY
        )
          @fetcher = fetcher
          @traceparent_key = traceparent_key
          @tracestate_key = tracestate_key
        end

        def inject!(digest, data)
          return if digest.nil?

          if (traceparent = build_traceparent(digest))
            data[@traceparent_key] = traceparent

            if (tracestate = TraceState.serialize_digest(digest))
              data[@tracestate_key] = tracestate
            end
          end

          data
        end

        def extract(data)
          fetcher = @fetcher.new(data)

          trace_id, parent_id, sampled, trace_flags = extract_traceparent(fetcher[@traceparent_key])

          return unless trace_id # Could not parse traceparent

          trace_state = TraceState.extract(fetcher[@tracestate_key])
          dd = trace_state.datadog
          ot = trace_state.open_telemetry

          tags = dd.tags
          sampling_priority = parse_priority_sampling(sampled, dd.sampling_priority) do |decision|
            case decision
            when String
              tags ||= {}
              tags[Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER] = decision
            when :drop
              tags&.delete(Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER)
            end
          end

          tags ||= {}
          tags[Tracing::Metadata::Ext::Distributed::TAG_DD_PARENT_ID] =
            dd.ts_parent_id || Tracing::Metadata::Ext::Distributed::DD_PARENT_ID_DEFAULT

          TraceDigest.new(
            span_id: parent_id,
            trace_id: trace_id,
            trace_origin: dd.origin,
            trace_sampling_priority: sampling_priority,
            trace_distributed_tags: tags,
            trace_flags: trace_flags,
            trace_state: trace_state.unknown_vendors,
            trace_state_unknown_fields: dd.unknown_fields,
            trace_otel_random_value: ot.random_value,
            trace_otel_threshold: ot.threshold,
            trace_otel_unknown_fields: ot.unknown_fields,
            span_remote: true,
          )
        end

        private

        # @see https://www.w3.org/TR/trace-context/#traceparent-header
        def build_traceparent(digest)
          build_traceparent_string(
            digest.trace_id,
            digest.span_id || 0, # Fall back to zero (invalid) if not present
            build_trace_flags(digest)
          )
        end

        # For the current version (00), the traceparent has the following format:
        #
        # `"#{version}-#{trace_id}-#{parent_id}-#{trace_flags}"`
        #
        # Where:
        #   * `version`: 2 hex-encoded digits, zero padded.
        #   * `trace_id`: 32 hex-encoded digits, zero padded.
        #   * `parent_id`: 16 hex-encoded digits, zero padded.
        #   * `trace_flags`: 2 hex-encoded digits, zero padded.
        #
        # All hex values should be lowercase.
        #
        # @param trace_id [Integer] 128-bit
        # @param parent_id [Integer] 64-bit
        # @param trace_flags [Integer] 8-bit
        def build_traceparent_string(trace_id, parent_id, trace_flags)
          "00-#{format("%032x", trace_id)}-#{format("%016x", parent_id)}-#{format("%02x", trace_flags)}"
        end

        # Sets the trace flag to an existing `trace_flags`.
        def build_trace_flags(digest)
          trace_flags = digest.trace_flags || DEFAULT_TRACE_FLAGS

          if digest.trace_sampling_priority
            if Tracing::Sampling::PrioritySampler.sampled?(digest.trace_sampling_priority)
              trace_flags |= TRACE_FLAGS_SAMPLED
            else
              trace_flags &= ~TRACE_FLAGS_SAMPLED
            end
          end

          trace_flags
        end

        def extract_traceparent(traceparent)
          trace_id, parent_id, trace_flags = parse_traceparent_string(traceparent)

          # Return unless all traceparent fields are valid.
          return unless trace_id && !trace_id.zero? && parent_id && !parent_id.zero? && trace_flags

          sampled = parse_sampled_flag(trace_flags)

          [trace_id, parent_id, sampled, trace_flags]
        end

        def parse_traceparent_string(traceparent)
          return unless traceparent
          return if traceparent.bytesize > TRACEPARENT_MAX_SIZE_LIMIT

          traceparent = traceparent.strip

          version, trace_id, parent_id, trace_flags, extra = traceparent.split("-", 5)

          return unless version && trace_id && parent_id && trace_flags
          return if version.size != 2 || trace_id.size != 32 || parent_id.size != 16 || trace_flags.size != 2
          return if version[0] < "0" || version[0] > "f" || version[1] < "0" || version[1] > "f"

          return if version == INVALID_VERSION

          # Extra fields are not allowed in version 00, but we have to be lenient for future versions.
          return if version == SPEC_VERSION && extra

          [Integer(trace_id, 16), Integer(parent_id, 16), Integer(trace_flags, 16)]
        rescue ArgumentError # Conversion to integer failed
          nil
        end

        def parse_sampled_flag(trace_flags)
          trace_flags & TRACE_FLAGS_SAMPLED
        end

        # If `sampled` and `sampling_priority` disagree, `sampled` overrides the decision.
        # @return [Integer] one of the {Datadog::Tracing::Sampling::Ext::Priority} values
        # @yieldparam the new decision maker (either :drop or a new decision maker String value).
        def parse_priority_sampling(sampled, sampling_priority)
          if sampled == 1
            if sampling_priority && Tracing::Sampling::PrioritySampler.sampled?(sampling_priority)
              # Both sampling fields agree.
              sampling_priority
            else
              # Sampling fields disagree.
              # Let's force the trace to be kept, while also updating the decision maker to ourselves.
              yield Tracing::Sampling::Ext::Decision::DEFAULT
              sampled
            end
          elsif sampling_priority && !Tracing::Sampling::PrioritySampler.sampled?(sampling_priority)
            sampling_priority
          # Both sampling fields agree.
          else
            # Sampling fields disagree.
            # Let's drop the trace and remove the sampling decision tag, as dropped spans don't carry sampling decision.
            yield :drop
            sampled
          end
        end

        TRACEPARENT_MAX_SIZE_LIMIT = 512
        private_constant :TRACEPARENT_MAX_SIZE_LIMIT

        # Version 0xFF is invalid as per spec
        # @see https://www.w3.org/TR/trace-context/#version
        INVALID_VERSION = "ff"
        private_constant :INVALID_VERSION

        # Empty 8-bit `trace-flags`.
        # @see https://www.w3.org/TR/trace-context/#trace-flags
        DEFAULT_TRACE_FLAGS = 0b00000000
        private_constant :DEFAULT_TRACE_FLAGS

        # Bit-mask for `trace-flags` that represents a sampled span (sampled==true).
        # @see https://www.w3.org/TR/trace-context/#trace-flags
        TRACE_FLAGS_SAMPLED = 0b00000001
        private_constant :TRACE_FLAGS_SAMPLED
      end
    end
  end
end
