# frozen_string_literal: true

require_relative "../../core/utils"
require_relative "open_telemetry_tracestate_codec"

module Datadog
  module Tracing
    module Distributed
      # Builds and parses the vendor members of a W3C `tracestate` header.
      #
      # @api private
      module TraceState
        module_function

        def build(digest)
          leading_vendors = select_leading_vendors(build_dd_vendor(digest), build_ot_vendor(digest))
          vendors = split(digest.trace_state)

          # With nothing of our own to inject, forward the upstream tracestate unchanged.
          if leading_vendors.empty?
            return unless vendors && !vendors.empty?

            return vendors.join(",")
          end

          # We are prepending our own vendors, so delete any existing `dd=`/`ot=`
          # vendors to avoid duplicates.
          vendors&.reject! { |vendor| vendor.start_with?("dd=", "ot=") }

          tracestate = leading_vendors.join(",")
          if vendors && !vendors.empty?
            vendors.first(TRACESTATE_MAX_LIST_VENDORS - leading_vendors.size).each do |vendor|
              break if tracestate.bytesize + vendor.bytesize + 1 > TRACESTATE_MAX_SIZE_LIMIT

              tracestate << "," << vendor
            end
          end

          tracestate
        end

        # Parses the Datadog and OpenTelemetry members, leaving the other vendors untouched.
        def extract(tracestate)
          vendors = split(tracestate) || []
          dd_vendor = pop_vendor(vendors, "dd=")
          ot_vendor = pop_vendor(vendors, "ot=")

          ExtractedVendors.new(
            vendors.empty? ? nil : vendors.join(","),
            extract_datadog_fields(dd_vendor),
            OpenTelemetryTracestateCodec.extract_otel_fields(ot_vendor),
          )
        end

        def build_dd_vendor(digest)
          vendor = +"dd="
          append_to_vendor(vendor, last_dd_parent_id(digest))
          append_to_vendor(vendor, "s:#{digest.trace_sampling_priority};") if digest.trace_sampling_priority
          append_to_vendor(vendor, "o:#{serialize_origin(digest.trace_origin)};") if digest.trace_origin

          # Replacing this by safe navigation has different behavior on Rubies <= 3.0.
          # It causes a LocalJumpError in the CI.
          if digest.trace_distributed_tags # rubocop:disable Style/SafeNavigation
            digest.trace_distributed_tags.each do |name, value|
              field = "t.#{serialize_tag_key(name)}:#{serialize_tag_value(value)};"
              break unless append_to_vendor(vendor, field)
            end
          end

          append_to_vendor(vendor, digest.trace_state_unknown_fields) if digest.trace_state_unknown_fields
          vendor.chop! if vendor.bytesize > 3
          vendor
        end

        def build_ot_vendor(digest)
          fields = digest.trace_otel_sampling_fields
          return unless fields || digest.trace_otel_unknown_fields

          vendor = +"ot="
          append_to_vendor(vendor, "rv:#{fields.random_value};") if fields&.random_value
          append_to_vendor(vendor, "th:#{fields.threshold};") if fields&.threshold
          append_to_vendor(vendor, digest.trace_otel_unknown_fields) if digest.trace_otel_unknown_fields
          vendor.chop! if vendor.bytesize > 3
          vendor
        end

        def select_leading_vendors(dd_vendor, ot_vendor)
          leading_vendors = []

          leading_vendors << dd_vendor if dd_vendor.bytesize > 3

          if ot_vendor && ot_vendor.bytesize > 3
            combined_size = leading_vendors.sum { |vendor| vendor.bytesize } +
              leading_vendors.size + ot_vendor.bytesize
            leading_vendors << ot_vendor if combined_size <= TRACESTATE_MAX_SIZE_LIMIT
          end

          leading_vendors
        end

        def append_to_vendor(vendor, field)
          return true if field.empty?
          return false if vendor.bytesize + field.bytesize > (TRACESTATE_VALUE_SIZE_LIMIT + 1)

          vendor << field
          true
        end

        def last_dd_parent_id(digest)
          if !digest.span_remote
            "p:#{format("%016x", digest.span_id || 0)};" # Fall back to zero (invalid) if not present
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
          value = INVALID_ORIGIN_CHARS.match?(value) ? value.gsub(INVALID_ORIGIN_CHARS, "_") : value
          REMAP_ORIGIN_CHARS.match?(value) ? value.gsub(REMAP_ORIGIN_CHARS, "~") : value
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
          serialized = INVALID_TAG_VALUE_CHARS.match?(value) ? value.gsub(INVALID_TAG_VALUE_CHARS, "_") : value
          # DEV: Checking for an unlikely '=' is faster than a no-op `tr`.
          serialized.include?("=") ? serialized.tr("=", "~") : serialized
        end

        def extract_datadog_fields(value)
          return DatadogFields.new unless value

          # @type var sampling_priority: ::Integer?
          # @type var origin: ::String?
          # @type var ts_parent_id: ::String?
          # @type var tags: ::Hash[::String, ::String]?
          # @type var unknown_fields: ::String?
          sampling_priority = nil
          origin = nil
          ts_parent_id = nil
          tags = nil
          unknown_fields = nil

          value.split(";").each do |pair|
            key, field = pair.split(":", 2)
            case key
            when "s"
              sampling_priority = begin
                Integer(field)
              rescue
                nil
              end
            when "o"
              origin = field
            when "p"
              ts_parent_id = field
            when /^t\./
              key = key.to_s
              field = field.to_s
              key.slice!(0..1)
              next if key == Tracing::Metadata::Ext::Distributed::TID

              field.tr!("~", "=")
              current_tags = tags || {}
              current_tags["#{Tracing::Metadata::Ext::Distributed::TAGS_PREFIX}#{key}"] = field
              tags = current_tags
            else
              current_unknown_fields = unknown_fields || +""
              current_unknown_fields << pair << ";"
              unknown_fields = current_unknown_fields
            end
          end

          DatadogFields.new(sampling_priority, origin, ts_parent_id, tags, unknown_fields)
        end

        def pop_vendor(vendors, prefix)
          index = vendors.index { |vendor| vendor.start_with?(prefix) }
          return unless index

          vendors.delete_at(index).delete_prefix(prefix)
        end

        # Partial members must not be propagated, but complete members within the limits are retained.
        def split(tracestate)
          return if tracestate.nil? || tracestate.empty?

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

          # The extra result lets us detect an over-limit list. Splitting at the limit
          # would fold every remaining member into the final string instead.
          vendors = tracestate.split(",", TRACESTATE_MAX_LIST_VENDORS + 1)
          vendors.pop if vendors.length > TRACESTATE_MAX_LIST_VENDORS || remove_last_vendor
          vendors.each(&:strip!)

          # Trailing delimiters and whitespace-only trailing members become empty after stripping.
          vendors.pop while vendors.last == ""
          vendors
        end

        ExtractedVendors = Struct.new(:tracestate, :dd, :ot)
        DatadogFields = Struct.new(:sampling_priority, :origin, :ts_parent_id, :tags, :unknown_fields)

        TRACESTATE_MAX_SIZE_LIMIT = 512
        TRACESTATE_MAX_LIST_VENDORS = 32
        TRACESTATE_VALUE_SIZE_LIMIT = 256

        INVALID_ORIGIN_CHARS = /[\u0000-\u0019,;~\u007F-\u{10FFFF}]/.freeze
        REMAP_ORIGIN_CHARS = /=/.freeze
        INVALID_TAG_KEY_CHARS = /[\u0000-\u0020,=\u007F-\u{10FFFF}]/.freeze
        INVALID_TAG_VALUE_CHARS = /[\u0000-\u001F,;\u007E-\u{10FFFF}]/.freeze

        private_constant \
          :ExtractedVendors,
          :DatadogFields,
          :TRACESTATE_MAX_SIZE_LIMIT,
          :TRACESTATE_MAX_LIST_VENDORS,
          :TRACESTATE_VALUE_SIZE_LIMIT,
          :INVALID_ORIGIN_CHARS,
          :REMAP_ORIGIN_CHARS,
          :INVALID_TAG_KEY_CHARS,
          :INVALID_TAG_VALUE_CHARS
      end
    end
  end
end
