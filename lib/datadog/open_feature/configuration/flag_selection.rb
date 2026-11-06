# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Configuration
      # Canonical flag selection a provider requests, or the reason it is not sent.
      class FlagSelection
        # Limits shared with the server: https://github.com/DataDog/ffe-system-test-data/blob/main/flag-selection/README.md
        MAX_VALUES = 31
        MAX_VALUE_BYTES = 200
        # Fastly answers longer URLs with 414 URI Too Long: https://docs.fastly.com/products/network-services-resource-limits
        MAX_URL_BYTES = 8192

        MALFORMED_SELECTION = "malformed_selection"
        TOO_MANY_VALUES = "too_many_values"
        INVALID_KEY_PATTERN = "invalid_key_pattern"
        INVALID_TAG = "invalid_tag"

        LIST_KEYS = {
          :tags => :tags,
          "tags" => :tags,
          :key_patterns => :key_patterns,
          "key_patterns" => :key_patterns,
        }.freeze

        # Not String#strip, which misses Unicode White_Space and strips NUL.
        SURROUNDING_WHITE_SPACE = /\A\p{White_Space}+|\p{White_Space}+\z/
        # RFC 3986 unreserved characters. Form encoding would send a space as "+".
        RESERVED_BYTE = /[^A-Za-z0-9\-._~]/n

        class << self
          # Never raises: an unusable option is returned as a dropped selection.
          def canonicalize(option)
            return if option.nil?

            raw_tags, raw_key_patterns = utf8_lists(option)
            return new(drop_reason: MALFORMED_SELECTION) unless raw_tags && raw_key_patterns

            tags = canonical_list(raw_tags)
            key_patterns = canonical_list(raw_key_patterns)
            drop_reason = limit_violation(tags, key_patterns)
            return new(drop_reason: drop_reason) if drop_reason
            return if tags.empty? && key_patterns.empty?

            new(tags: tags, key_patterns: key_patterns)
          rescue EncodingError, ArgumentError
            new(drop_reason: MALFORMED_SELECTION)
          end

          private

          def utf8_lists(option)
            return unless option.is_a?(Hash)

            raw_lists = {}
            ambiguous = false
            option.each_pair do |key, value|
              name = LIST_KEYS[key]
              next unless name

              ambiguous ||= raw_lists.key?(name)
              raw_lists[name] = value
            end
            # Both the Symbol and the String spelling of one list leave the selection ambiguous.
            return if ambiguous

            tags = utf8_list(raw_lists[:tags])
            key_patterns = utf8_list(raw_lists[:key_patterns])
            [tags, key_patterns] if tags && key_patterns
          end

          def utf8_list(value)
            return [] if value.nil?
            return unless value.is_a?(Array) && value.all? { |element| element.is_a?(String) }

            # A UTF-8 String with invalid bytes passes #encode unchanged.
            utf8_values = value.map { |element| element.encode(Encoding::UTF_8) }
            utf8_values if utf8_values.all?(&:valid_encoding?)
          end

          def canonical_list(values)
            trimmed = values.map { |value| value.gsub(SURROUNDING_WHITE_SPACE, "") }
            # String#<=> compares bytes, which is UTF-8 byte order.
            trimmed.reject(&:empty?).uniq.sort.map(&:freeze)
          end

          def limit_violation(tags, key_patterns)
            if tags.size > MAX_VALUES || key_patterns.size > MAX_VALUES
              TOO_MANY_VALUES
            elsif key_patterns.any? { |pattern| pattern.bytesize > MAX_VALUE_BYTES }
              INVALID_KEY_PATTERN
            elsif tags.any? { |tag| tag.bytesize > MAX_VALUE_BYTES }
              INVALID_TAG
            end
          end
        end

        attr_reader :tags, :key_patterns, :drop_reason

        def initialize(tags: [], key_patterns: [], drop_reason: nil)
          @tags = tags.freeze
          @key_patterns = key_patterns.freeze
          @drop_reason = drop_reason
          freeze
        end

        def dropped?
          !@drop_reason.nil?
        end

        def query
          parameters = tags.map { |tag| "selected_flag_tags=#{encode(tag)}" } +
            key_patterns.map { |pattern| "selected_flag_key_patterns=#{encode(pattern)}" }
          parameters.join("&")
        end

        def ==(other)
          other.is_a?(FlagSelection) &&
            drop_reason == other.drop_reason &&
            tags == other.tags &&
            key_patterns == other.key_patterns
        end

        private

        def encode(value)
          value.b.gsub(RESERVED_BYTE) { |byte| format("%%%02X", byte.ord) }
        end
      end
    end
  end
end
