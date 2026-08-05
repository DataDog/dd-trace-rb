# frozen_string_literal: true

require_relative "../../core/utils"
require_relative "open_telemetry_tracestate_codec"
require_relative "helpers"

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

            if (tracestate = build_tracestate(digest))
              data[@tracestate_key] = tracestate
            end
          end

          data
        end

        def extract(data)
          fetcher = @fetcher.new(data)

          trace_id, parent_id, sampled, trace_flags = extract_traceparent(fetcher[@traceparent_key])

          return unless trace_id # Could not parse traceparent

          parsed = extract_tracestate(fetcher[@tracestate_key])
          dd = parsed.dd
          ot = parsed.ot

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
            trace_state: parsed.tracestate,
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

        # @see https://www.w3.org/TR/trace-context/#tracestate-header
        def build_tracestate(digest)
          dd_vendor = build_dd_vendor(digest)
          ot_vendor = build_ot_vendor(digest)
          leading_vendors = select_leading_vendors(dd_vendor, ot_vendor)

          vendors = split_tracestate(digest.trace_state)

          # With nothing of our own to inject, forward the upstream tracestate unchanged.
          if leading_vendors.empty?
            return unless vendors && !vendors.empty?

            return vendors.join(",")
          end

          # We are prepending our own vendors, so delete any existing `dd=`/`ot=`
          # vendors to avoid duplicates.
          vendors&.reject! { |v| v.start_with?("dd=", "ot=") }

          tracestate = leading_vendors.join(",")

          if vendors && !vendors.empty?
            # Ensure the list has at most TRACESTATE_MAX_LIST_VENDORS entries total,
            # reserving the leading vendors we prepended.
            vendors.first(TRACESTATE_MAX_LIST_VENDORS - leading_vendors.size).each do |vendor|
              break if tracestate.bytesize + vendor.bytesize + 1 > TRACESTATE_MAX_SIZE_LIMIT

              tracestate << "," << vendor
            end
          end

          tracestate
        end

        # Builds the `dd=` tracestate vendor.
        def build_dd_vendor(digest)
          dd_vendor = +"dd="
          append_to_vendor(dd_vendor, last_dd_parent_id(digest))
          append_to_vendor(dd_vendor, "s:#{digest.trace_sampling_priority};") if digest.trace_sampling_priority
          append_to_vendor(dd_vendor, "o:#{serialize_origin(digest.trace_origin)};") if digest.trace_origin

          # Replacing this by safe navigation seems to have a different behaviour on Rubies <= 3.0.
          # It cause a LocalJumpError in the CI.
          if digest.trace_distributed_tags # rubocop:disable Style/SafeNavigation
            digest.trace_distributed_tags.each do |name, value|
              tag = "t.#{serialize_tag_key(name)}:#{serialize_tag_value(value)};"

              # If tracestate size limit is exceeded, drop the remaining data.
              break unless append_to_vendor(dd_vendor, tag)
            end
          end

          append_to_vendor(dd_vendor, digest.trace_state_unknown_fields) if digest.trace_state_unknown_fields

          dd_vendor
        end

        # Builds the OpenTelemetry consistent probability sampling `ot=` tracestate vendor,
        # or nil when the digest carries no OTel data to emit.
        # @see https://opentelemetry.io/docs/specs/otel/trace/tracestate-probability-sampling/
        def build_ot_vendor(digest)
          return unless digest.trace_otel_random_value || digest.trace_otel_threshold || digest.trace_otel_unknown_fields

          ot_vendor = +"ot="
          append_to_vendor(ot_vendor, "rv:#{digest.trace_otel_random_value};") if digest.trace_otel_random_value
          append_to_vendor(ot_vendor, "th:#{digest.trace_otel_threshold};") if digest.trace_otel_threshold
          append_to_vendor(ot_vendor, digest.trace_otel_unknown_fields) if digest.trace_otel_unknown_fields
          ot_vendor
        end

        # Picks which of `dd_vendor`/`ot_vendor` are non-empty and must lead the tracestate
        # (in that order, so they survive truncation of a crowded header), each with its
        # trailing `;` removed.
        #
        # `dd=` and `ot=` are each individually capped at TRACESTATE_VALUE_SIZE_LIMIT bytes,
        # but together (plus the separating comma) they could still exceed
        # TRACESTATE_MAX_SIZE_LIMIT. Rather than partially truncate `ot=` into a mangled
        # vendor, it is dropped entirely, mirroring how some OTel SDKs drop an oversized
        # tracestate.
        def select_leading_vendors(dd_vendor, ot_vendor)
          leading_vendors = []

          if dd_vendor.bytesize > 3
            dd_vendor.chop! # Removes trailing `;` from Datadog trace state string.
            leading_vendors << dd_vendor
          end

          if ot_vendor && ot_vendor.bytesize > 3
            ot_vendor.chop! # Removes trailing `;` from OpenTelemetry trace state string.

            combined_size = leading_vendors.sum(&:bytesize) + leading_vendors.size + ot_vendor.bytesize
            leading_vendors << ot_vendor if combined_size <= TRACESTATE_MAX_SIZE_LIMIT
          end

          leading_vendors
        end

        # Appends a Datadog tracestate field when it fits.
        def append_to_vendor(vendor, field)
          return true if field.empty?

          # We add 1 to the limit because of the trailing semicolon, which will be removed before returning.
          return false if vendor.bytesize + field.bytesize > (TRACESTATE_VALUE_SIZE_LIMIT + 1)

          vendor << field
          true
        end

        def last_dd_parent_id(digest)
          if !digest.span_remote
            span_id = digest.span_id || 0 # Fall back to zero (invalid) if not present
            "p:#{format("%016x", span_id)};"
          elsif digest.trace_distributed_tags&.key?(Tracing::Metadata::Ext::Distributed::TAG_DD_PARENT_ID)
            "p:#{digest.trace_distributed_tags[Tracing::Metadata::Ext::Distributed::TAG_DD_PARENT_ID]};"
          else
            ""
          end
        end

        # If any characters in <origin_value> are invalid, replace each invalid character with 0x5F (underscore).
        # Invalid characters are: characters outside the ASCII range 0x20 to 0x7E,
        # 0x2C (comma), 0x3B (semi-colon), and 0x7E (tilde).
        # Then, remap 0x3D (equals) to 0x7E (tilde)
        def serialize_origin(value)
          # DEV: It's unlikely that characters will be out of range, as they mostly
          # DEV: come from Datadog-controlled sources.
          # DEV: Trying to `match?` is measurably faster than a `gsub` that does not match.
          value = if INVALID_ORIGIN_CHARS.match?(value)
            value.gsub(INVALID_ORIGIN_CHARS, "_")
          else
            value
          end

          if REMAP_ORIGIN_CHARS.match?(value)
            value.gsub(REMAP_ORIGIN_CHARS, "~")
          else
            value
          end
        end

        # Serialize `_dd.p.{key}` by first removing the `_dd.p.` prefix.
        # Then replacing invalid characters with `_`.
        #
        # The argument `name` is always frozen.
        # Returns a new String object for the serialized key.
        def serialize_tag_key(name)
          key = name.delete_prefix(Tracing::Metadata::Ext::Distributed::TAGS_PREFIX)

          # DEV: It's unlikely that characters will be out of range, as they mostly
          # DEV: come from Datadog-controlled sources.
          # DEV: Trying to `match?` is measurably faster than a `gsub!` that does not match.
          key.gsub!(INVALID_TAG_KEY_CHARS, "_") if INVALID_TAG_KEY_CHARS.match?(key)

          key
        end

        # Replaces invalid characters with `_`, then replaces `=` with `~`.
        #
        # The argument `value` belongs to {TraceDigest}, thus should not be directly modified.
        # Returns a new String object for the serialized value.
        def serialize_tag_value(value)
          # DEV: It's unlikely that characters will be out of range, as they mostly
          # DEV: come from Datadog-controlled sources.
          # DEV: Trying to `match?` is measurably faster than a `gsub` that does not match.
          ret = if INVALID_TAG_VALUE_CHARS.match?(value)
            value.gsub(INVALID_TAG_VALUE_CHARS, "_")
          else
            value
          end

          # DEV: Checking for an unlikely '=' is faster than a no-op `tr`.
          if ret.include?("=")
            ret.tr("=", "~")
          else
            ret
          end
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

        # Parses the W3C `tracestate` into the Datadog (`dd=`) and OpenTelemetry (`ot=`)
        # vendors, leaving the remaining vendors untouched.
        #
        # @return [ExtractedTracestate]
        def extract_tracestate(tracestate)
          vendors = split_tracestate(tracestate) || []

          # Remove the Datadog and OpenTelemetry vendors here so they are re-emitted from the
          # parsed values on injection rather than passed through as opaque vendors.
          dd_vendor = pop_vendor(vendors, "dd=")
          ot_vendor = pop_vendor(vendors, "ot=")

          ExtractedTracestate.new(
            vendors.join(","),
            extract_datadog_fields(dd_vendor),
            OpenTelemetryTracestateCodec.extract_otel_fields(ot_vendor),
          )
        end

        # Removes the first vendor with the given `prefix` (e.g. `"dd="`) and returns
        # its value (the part after the prefix), or nil when absent.
        def pop_vendor(vendors, prefix)
          idx = vendors.index { |v| v.start_with?(prefix) }
          return unless idx

          vendors.delete_at(idx).delete_prefix(prefix)
        end

        def extract_datadog_fields(dd_tracestate)
          return ExtractedDatadogFields.new unless dd_tracestate

          sampling_priority = nil
          origin = nil
          ts_parent_id = nil
          tags = nil
          unknown_fields = nil

          # DEV: Since Ruby 2.6 `split` can receive a block, so `each` can be removed then.
          dd_tracestate.split(";").each do |pair|
            key, value = pair.split(":", 2)
            case key
            when "s"
              sampling_priority = begin
                Integer(value)
              rescue
                nil
              end
            when "o"
              origin = value
            when "p"
              ts_parent_id = value
            when /^t\./
              key.slice!(0..1) # Delete `t.` prefix

              # Ignore the high order 64 bit trace id propagation tag to avoid confusion,
              # the single source of truth is from traceparent
              next if key == Tracing::Metadata::Ext::Distributed::TID

              value = deserialize_tag_value(value)

              tags ||= {}
              tags["#{Tracing::Metadata::Ext::Distributed::TAGS_PREFIX}#{key}"] = value
            else
              unknown_fields ||= +""
              unknown_fields << pair
              unknown_fields << ";"
            end
          end

          ExtractedDatadogFields.new(sampling_priority, origin, ts_parent_id, tags, unknown_fields)
        end

        # Restore `~` back to `=`.
        def deserialize_tag_value(value)
          value.tr!("~", "=")
          value
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

        # We MUST NOT propagate partial vendors, but we SHOULD try
        # to parse as much of the tracestate as possible.
        def split_tracestate(tracestate)
          return unless tracestate

          remove_last_vendor = false
          if tracestate.bytesize > TRACESTATE_MAX_SIZE_LIMIT
            # We parse 1 byte over the limit to detect if the last vendor
            # is a partial vendor (toss) or ends exactly at the limit (keep).
            remove_last_vendor = tracestate.byteslice(TRACESTATE_MAX_SIZE_LIMIT, 1) != ","

            # To ensure we don't have a trailing partial UTF-8 codepoint, we keep one extra byte
            # and safely remove it with `#chop`.
            # `#chop` walks back the string until it finds a valid character boundary and deletes
            # from there.
            tracestate = tracestate.byteslice(0, TRACESTATE_MAX_SIZE_LIMIT + 1) #: String
            tracestate = tracestate.chop
          end

          tracestate = ::Datadog::Core::Utils.utf8_encode(tracestate, placeholder: nil)
          return unless tracestate

          vendors = tracestate.split(",", TRACESTATE_MAX_LIST_VENDORS + 1)
          if vendors.length > TRACESTATE_MAX_LIST_VENDORS || remove_last_vendor
            vendors.pop
          end

          vendors.each(&:strip!)
          vendors.pop while vendors.last == ""
          vendors
        end

        ExtractedTracestate = Struct.new(:tracestate, :dd, :ot)
        private_constant :ExtractedTracestate

        ExtractedDatadogFields = Struct.new(:sampling_priority, :origin, :ts_parent_id, :tags, :unknown_fields)
        private_constant :ExtractedDatadogFields

        TRACEPARENT_MAX_SIZE_LIMIT = 512
        private_constant :TRACEPARENT_MAX_SIZE_LIMIT

        TRACESTATE_MAX_SIZE_LIMIT = 512
        private_constant :TRACESTATE_MAX_SIZE_LIMIT

        TRACESTATE_MAX_LIST_VENDORS = 32
        private_constant :TRACESTATE_MAX_LIST_VENDORS

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

        # The limit is inclusive: sizes *greater* than 256 are disallowed.
        # @see https://www.w3.org/TR/trace-context/#value
        TRACESTATE_VALUE_SIZE_LIMIT = 256
        private_constant :TRACESTATE_VALUE_SIZE_LIMIT

        # Replace all characters with `_`, except ASCII characters 0x20-0x7E.
        # Additionally, `,`, ';', and `~` must also be replaced by `_`.
        INVALID_ORIGIN_CHARS = /[\u0000-\u0019,;~\u007F-\u{10FFFF}]/.freeze
        private_constant :INVALID_ORIGIN_CHARS

        # Additionally, remap `=` to `~`
        REMAP_ORIGIN_CHARS = /=/.freeze
        private_constant :REMAP_ORIGIN_CHARS

        # Replace all characters with `_`, except ASCII characters 0x21-0x7E.
        # Additionally, `,` and `=` must also be replaced by `_`.
        INVALID_TAG_KEY_CHARS = /[\u0000-\u0020,=\u007F-\u{10FFFF}]/.freeze
        private_constant :INVALID_TAG_KEY_CHARS

        # Replace all characters with `_`, except ASCII characters 0x20-0x7D.
        # Additionally, `,` and `;` must also be replaced by `_`.
        INVALID_TAG_VALUE_CHARS = /[\u0000-\u001F,;\u007E-\u{10FFFF}]/.freeze
        private_constant :INVALID_TAG_VALUE_CHARS
      end
    end
  end
end
