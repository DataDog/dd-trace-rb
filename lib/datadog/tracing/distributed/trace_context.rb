# frozen_string_literal: true

module Datadog
  module Tracing
    module Distributed
      # W3C Trace Context propagator implementation, version 00.
      # The trace is propagated through two fields: `traceparent` and `tracestate`.
      # @see https://www.w3.org/TR/trace-context/
      class TraceContext
        TRACEPARENT_KEY = 'traceparent'
        TRACESTATE_KEY = 'tracestate'
        SPEC_VERSION = '00'

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

            if (tracestate = build_tracestate(digest))
              data[@tracestate_key] = tracestate
            end
          end

          data
        end

        def extract(data)
          fetcher = @fetcher.new(data)

          trace_id, dd_trace_id, parent_id, sampled, trace_flags = extract_traceparent(fetcher[@traceparent_key])

          return unless trace_id # Could not parse traceparent

          tracestate, sampling_priority, origin, tags, unknown_fields = extract_tracestate(fetcher[@tracestate_key])

          sampling_priority = parse_priority_sampling(sampled, sampling_priority)

          TraceDigest.new(
            span_id: parent_id,
            trace_id: dd_trace_id,
            trace_origin: origin,
            trace_sampling_priority: sampling_priority,
            trace_distributed_tags: tags,
            trace_distributed_id: trace_id,
            trace_flags: trace_flags,
            trace_state: tracestate,
            trace_state_unknown_fields: unknown_fields,
          )
        end

        private

        # Refinements to ensure newer rubies do not suffer performance impact
        # by needing to use older APIs.
        module Refine
          # Backport `Regexp::match?` because it is measurably the most performant
          # way to check if a string matches a regular expression.
          unless Regexp.method_defined?(:match?)
            refine ::Regexp do
              def match?(*args)
                !match(*args).nil?
              end
            end
          end

          unless String.method_defined?(:delete_prefix)
            refine ::String do
              def delete_prefix(prefix)
                prefix = prefix.to_s
                if rindex(prefix, 0)
                  self[prefix.length..-1]
                else
                  dup
                end
              end
            end
          end
        end
        using Refine

        # @see https://www.w3.org/TR/trace-context/#traceparent-header
        def build_traceparent(digest)
          build_traceparent_string(
            digest.trace_distributed_id || digest.trace_id,
            digest.span_id,
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
          "00-#{format('%032x', trace_id)}-#{format('%016x', parent_id)}-#{format('%02x', trace_flags)}"
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

        # @see https://www.w3.org/TR/trace-context/#tracestate-header
        def build_tracestate(digest)
          tracestate = String.new('dd=')
          tracestate << "s:#{digest.trace_sampling_priority};" if digest.trace_sampling_priority
          tracestate << "o:#{serialize_origin(digest.trace_origin)};" if digest.trace_origin

          if digest.trace_distributed_tags
            digest.trace_distributed_tags.each do |name, value|
              tag = "t.#{serialize_tag_key(name)}:#{serialize_tag_value(value)};"

              # If tracestate size limit is exceed, drop the remaining data.
              # String#bytesize is used because only ASCII characters are allowed.
              #
              # We add 1 to the limit because of the trailing comma, which will be removed before returning.
              break if tracestate.bytesize + tag.bytesize > (TRACESTATE_VALUE_SIZE_LIMIT + 1)

              tracestate << tag
            end
          end

          tracestate << digest.trace_state_unknown_fields if digest.trace_state_unknown_fields

          # Is there any Datadog-specific information to propagate.
          # Check for > 3 size because the empty prefix `dd=` has 3 characters.
          if tracestate.size > 3
            # Propagate upstream tracestate with `dd=...` appended to the list
            tracestate.chop! # Removes trailing `;` from Datadog trace state string.

            if digest.trace_state
              # Delete existing `dd=` tracestate fields, if present.
              vendors = split_tracestate(digest.trace_state)
              vendors.reject! { |v| v.start_with?('dd=') }
            end

            if vendors && !vendors.empty?
              # Ensure the list has at most 31 elements, as we need to prepend Datadog's
              # entry and the limit is 32 elements total.
              vendors = vendors[0..30]
              "#{tracestate},#{vendors.join(',')}"
            else
              tracestate.to_s
            end
          else
            digest.trace_state # Propagate upstream tracestate with no Datadog changes
          end
        end

        # If any characters in <origin_value> are invalid, replace each invalid character with 0x5F (underscore).
        # Invalid characters are: characters outside the ASCII range 0x20 to 0x7E, 0x2C (comma), and 0x3D (equals).
        def serialize_origin(value)
          # DEV: It's unlikely that characters will be out of range, as they mostly
          # DEV: come from Datadog-controlled sources.
          # DEV: Trying to `match?` is measurably faster than a `gsub` that does not match.
          if INVALID_ORIGIN_CHARS.match?(value)
            value.gsub(INVALID_ORIGIN_CHARS, '_')
          else
            value
          end
        end

        # Serialize `_dd.p.{key}` by first removing the `_dd.p.` prefix.
        # Then replacing invalid characters with `_`.
        def serialize_tag_key(name)
          key = name.delete_prefix(Tracing::Metadata::Ext::Distributed::TAGS_PREFIX)

          # DEV: It's unlikely that characters will be out of range, as they mostly
          # DEV: come from Datadog-controlled sources.
          # DEV: Trying to `match?` is measurably faster than a `gsub` that does not match.
          if INVALID_TAG_KEY_CHARS.match?(key)
            key.gsub(INVALID_TAG_KEY_CHARS, '_')
          else
            key
          end
        end

        # Replaces invalid characters with `_`, then replaces `=` with `:`.
        def serialize_tag_value(value)
          # DEV: It's unlikely that characters will be out of range, as they mostly
          # DEV: come from Datadog-controlled sources.
          # DEV: Trying to `match?` is measurably faster than a `gsub` that does not match.
          ret = if INVALID_TAG_VALUE_CHARS.match?(value)
                  value.gsub(INVALID_TAG_VALUE_CHARS, '_')
                else
                  value
                end

          # DEV: Checking for an unlikely '=' is faster than a no-op `tr!`.
          ret.tr!('=', ':') if ret.include?('=')
          ret
        end

        def extract_traceparent(traceparent)
          trace_id, parent_id, trace_flags = parse_traceparent_string(traceparent)

          # Return unless all traceparent fields are valid.
          return unless trace_id && !trace_id.zero? && parent_id && !parent_id.zero? && trace_flags

          dd_trace_id = parse_datadog_trace_id(trace_id)
          sampled = parse_sampled_flag(trace_flags)

          [trace_id, dd_trace_id, parent_id, sampled, trace_flags]
        end

        def parse_traceparent_string(traceparent)
          return unless traceparent

          version, trace_id, parent_id, trace_flags, extra = traceparent.strip.split('-')

          return if version == INVALID_VERSION

          # Extra fields are not allowed in version 00, but we have to be lenient for future versions.
          return if version == SPEC_VERSION && extra

          # Invalid field sizes
          return if version.size != 2 || trace_id.size != 32 || parent_id.size != 16 || trace_flags.size != 2

          [Integer(trace_id, 16), Integer(parent_id, 16), Integer(trace_flags, 16)]
        rescue ArgumentError # Conversion to integer failed
          nil
        end

        # Datadog only allows 64 bits for the trace id.
        # We extract the lower 64 bits from the original 128-bit id.
        def parse_datadog_trace_id(trace_id)
          trace_id & 0xFFFFFFFFFFFFFFFF
        end

        def parse_sampled_flag(trace_flags)
          trace_flags & TRACE_FLAGS_SAMPLED
        end

        # @return [Array<String,Integer,String,Hash>] returns 4 values: tracestate, sampling_priority, origin, tags.
        def extract_tracestate(tracestate)
          return unless tracestate

          vendors = split_tracestate(tracestate)

          # Find Datadog's `dd=` tracestate field.
          idx = vendors.index { |v| v.start_with?('dd=') }
          return tracestate unless idx

          # Delete `dd=` prefix
          dd_tracestate = vendors.delete_at(idx)
          dd_tracestate.slice!(0..2)

          origin, sampling_priority, tags, unknown_fields = extract_datadog_fields(dd_tracestate)

          [vendors.join(','), sampling_priority, origin, tags, unknown_fields]
        end

        def extract_datadog_fields(dd_tracestate)
          sampling_priority = nil
          origin = nil
          tags = nil
          unknown_fields = nil

          # DEV: Since Ruby 2.6 `split` can receive a block, so `each` can be removed then.
          dd_tracestate.split(';').each do |pair|
            key, value = pair.split(':', 2)
            case key
            when 's'
              sampling_priority = Integer(value) rescue nil
            when 'o'
              origin = value
            when /^t\./
              key.slice!(0..1) # Delete `t.` prefix

              value = deserialize_tag_value(value)

              tags ||= {}
              tags["#{Tracing::Metadata::Ext::Distributed::TAGS_PREFIX}#{key}"] = value
            else
              unknown_fields ||= String.new
              unknown_fields << pair
              unknown_fields << ';'
            end
          end

          [origin, sampling_priority, tags, unknown_fields]
        end

        # Restore `:` back to `=`.
        def deserialize_tag_value(value)
          value.tr!(':', '=')
          value
        end

        # If `sampled` and `sampling_priority` disagree, `sampled` overrides the decision.
        # @return [Integer] one of the {Datadog::Tracing::Sampling::Ext::Priority} values
        def parse_priority_sampling(sampled, sampling_priority)
          # If both fields agree
          if sampling_priority &&
              (!Tracing::Sampling::PrioritySampler.sampled?(sampling_priority) && sampled == 0 || # Both drop
                Tracing::Sampling::PrioritySampler.sampled?(sampling_priority) && sampled == 1) # Both keep

            return sampling_priority # Return the richer `sampling_priority`
          end

          sampled # Sampled flag trumps `sampling_priority` on conflict
        end

        def split_tracestate(tracestate)
          tracestate.split(/[ \t]*,[ \t]*/)[0..31]
        end

        # Version 0xFF is invalid as per spec
        # @see https://www.w3.org/TR/trace-context/#version
        INVALID_VERSION = 'ff'
        private_constant :INVALID_VERSION

        # Empty 8-bit `trace-flags`.
        # @see https://www.w3.org/TR/trace-context/#trace-flags
        DEFAULT_TRACE_FLAGS = 0b00000000
        private_constant :DEFAULT_TRACE_FLAGS

        # Bit-mask for `trace-flags` that represents a sampled span (sampled==true).
        # @see https://www.w3.org/TR/trace-context/#trace-flags
        TRACE_FLAGS_SAMPLED = 0b00000001
        private_constant :TRACE_FLAGS_SAMPLED

        # The limit is inclusive: sizes *greater* than 256 are disallowed.
        # @see https://www.w3.org/TR/trace-context/#value
        TRACESTATE_VALUE_SIZE_LIMIT = 256
        private_constant :TRACESTATE_VALUE_SIZE_LIMIT

        # Replace all characters with `_`, except ASCII characters 0x20-0x7E.
        # Additionally, `,`, ';', and `=` must also be replaced by `_`.
        INVALID_ORIGIN_CHARS = /[\u0000-\u0019,;=\u007F-\u{10FFFF}]/.freeze
        private_constant :INVALID_ORIGIN_CHARS

        # Replace all characters with `_`, except ASCII characters 0x21-0x7E.
        # Additionally, `,` and `=` must also be replaced by `_`.
        INVALID_TAG_KEY_CHARS = /[\u0000-\u0020,=\u007F-\u{10FFFF}]/.freeze
        private_constant :INVALID_TAG_KEY_CHARS

        # Replace all characters with `_`, except ASCII characters 0x20-0x7E.
        # Additionally, `,`, ':' and `;` must also be replaced by `_`.
        INVALID_TAG_VALUE_CHARS = /[\u0000-\u001F,:;\u007F-\u{10FFFF}]/.freeze
        private_constant :INVALID_TAG_VALUE_CHARS
      end
    end
  end
end
