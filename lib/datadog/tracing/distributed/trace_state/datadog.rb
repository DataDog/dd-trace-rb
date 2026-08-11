# frozen_string_literal: true

require_relative "ext"

module Datadog
  module Tracing
    module Distributed
      class TraceState
        # Encodes and decodes Datadog propagation state.
        class Datadog
          class << self
            def from_digest(digest)
              ts_parent_id = if !digest.span_remote
                format("%016x", digest.span_id || 0)
              elsif digest.trace_distributed_tags&.key?(Tracing::Metadata::Ext::Distributed::TAG_DD_PARENT_ID)
                digest.trace_distributed_tags[Tracing::Metadata::Ext::Distributed::TAG_DD_PARENT_ID]
              end

              new(
                sampling_priority: digest.trace_sampling_priority,
                origin: digest.trace_origin,
                ts_parent_id: ts_parent_id,
                tags: digest.trace_distributed_tags,
                unknown_fields: digest.trace_state_unknown_fields,
              )
            end

            def from_tracestate_member(value)
              return new unless value

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

              new(
                sampling_priority: sampling_priority,
                origin: origin,
                ts_parent_id: ts_parent_id,
                tags: tags,
                unknown_fields: unknown_fields,
              )
            end

            # Serializes a {Hash<String,String>} into a `x-datadog-tags`-compatible
            # String.
            #
            # @param tags [Hash<String,String>] trace tag hash
            # @return [String] serialized tags hash
            # @raise [EncodingError] if tags cannot be serialized to the `x-datadog-tags` format
            def encode(tags)
              tags.map do |raw_key, raw_value|
                key = raw_key.to_s
                value = raw_value.to_s

                unless Ext::Datadog::VALID_KEY_CHARS.match?(key)
                  raise EncodingError, "Invalid key `#{key}` for value `#{value}`"
                end
                unless Ext::Datadog::VALID_VALUE_CHARS.match?(value)
                  raise EncodingError, "Invalid value `#{value}` for key `#{key}`"
                end

                "#{key}=#{value.strip}"
              end.join(",")
            rescue => e
              raise EncodingError, "Error encoding tags `#{tags}`: `#{e.class}: #{e.message}`"
            end

            # Deserializes a `x-datadog-tags`-formatted String into a {Hash<String,String>}.
            #
            # @param string [String] tags as serialized by {#encode}
            # @return [Hash<String,String>] decoded input as a hash of strings
            # @raise [DecodingError] if string does not conform to the `x-datadog-tags` format
            def decode(string)
              result = (string.split(",").map do |raw_tag|
                raw_tag.split("=", 2).tap do |raw_key, raw_value|
                  key = raw_key.to_s
                  value = raw_value.to_s

                  raise DecodingError, "Invalid key: #{key}" unless Ext::Datadog::VALID_KEY_CHARS.match?(key)
                  raise DecodingError, "Invalid value: #{value}" unless Ext::Datadog::VALID_VALUE_CHARS.match?(value)

                  value.strip!
                end
              end).to_h

              raise DecodingError, "Invalid empty tags: #{string}" if result.empty? && !string.empty?

              result
            end
          end

          # An error occurred during distributed tags encoding.
          # See {#message} for more information.
          class EncodingError < StandardError
          end

          # An error occurred during distributed tags decoding.
          # See {#message} for more information.
          class DecodingError < StandardError
          end

          attr_reader :sampling_priority, :origin, :ts_parent_id, :tags, :unknown_fields

          def initialize(sampling_priority: nil, origin: nil, ts_parent_id: nil, tags: nil, unknown_fields: nil)
            @sampling_priority = sampling_priority
            @origin = origin
            @ts_parent_id = ts_parent_id
            @tags = tags
            @unknown_fields = unknown_fields
          end

          # Builds the `dd=` tracestate member.
          def build
            vendor = +"dd="
            if ts_parent_id
              field = "p:#{ts_parent_id};"
              vendor << field if vendor.bytesize + field.bytesize <= (Ext::TRACESTATE_VALUE_SIZE_LIMIT + 1)
            end
            if sampling_priority
              field = "s:#{sampling_priority};"
              vendor << field if vendor.bytesize + field.bytesize <= (Ext::TRACESTATE_VALUE_SIZE_LIMIT + 1)
            end
            if origin
              field = "o:#{serialize_origin(origin)};"
              vendor << field if vendor.bytesize + field.bytesize <= (Ext::TRACESTATE_VALUE_SIZE_LIMIT + 1)
            end

            # Replacing this with safe navigation causes a LocalJumpError on Rubies <= 3.0.
            if tags # rubocop:disable Style/SafeNavigation
              tags.each do |name, value|
                tag_field = "t.#{serialize_tag_key(name)}:#{serialize_tag_value(value)};"
                break if vendor.bytesize + tag_field.bytesize > (Ext::TRACESTATE_VALUE_SIZE_LIMIT + 1)

                vendor << tag_field
              end
            end

            if unknown_fields && vendor.bytesize + unknown_fields.bytesize <= (Ext::TRACESTATE_VALUE_SIZE_LIMIT + 1)
              vendor << unknown_fields
            end
            return "" if vendor.bytesize == 3

            vendor.chop!
            vendor
          end

          private

          # If any characters in <origin_value> are invalid, replace each invalid character with 0x5F (underscore).
          # Invalid characters are: characters outside the ASCII range 0x20 to 0x7E,
          # 0x2C (comma), 0x3B (semi-colon), and 0x7E (tilde).
          # Then, remap 0x3D (equals) to 0x7E (tilde)
          def serialize_origin(value)
            # DEV: It's unlikely that characters will be out of range, as they mostly
            # DEV: come from Datadog-controlled sources.
            # DEV: Trying to `match?` is measurably faster than a `gsub` that does not match.
            invalid_chars = Ext::Datadog::INVALID_ORIGIN_CHARS
            value = invalid_chars.match?(value) ? value.gsub(invalid_chars, "_") : value
            remapped_chars = Ext::Datadog::REMAP_ORIGIN_CHARS
            remapped_chars.match?(value) ? value.gsub(remapped_chars, "~") : value
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
            invalid_chars = Ext::Datadog::INVALID_TAG_KEY_CHARS
            key.gsub!(invalid_chars, "_") if invalid_chars.match?(key)
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
            invalid_chars = Ext::Datadog::INVALID_TAG_VALUE_CHARS
            serialized = invalid_chars.match?(value) ? value.gsub(invalid_chars, "_") : value
            # DEV: Checking for an unlikely '=' is faster than a no-op `tr`.
            serialized.include?("=") ? serialized.tr("=", "~") : serialized
          end
        end
      end
    end
  end
end
