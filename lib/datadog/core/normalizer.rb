# frozen_string_literal: true

module Datadog
  module Core
    module Normalizer
      module_function

      INVALID_TAG_CHARACTERS = %r{[^\p{L}0-9_\-:./]}
      LEADING_INVALID_CHARS_NO_DIGITS = %r{\A[^\p{L}:]++}
      LEADING_INVALID_CHARS_WITH_DIGITS = %r{\A[^\p{L}0-9:./\-]++}
      MAX_BYTE_SIZE = 200
      MAX_BYTE_SIZE_BUFFER = MAX_BYTE_SIZE * 2
      TRAILING_UNDERSCORES = %r{_++\z}
      VALID_ASCII_TAG = %r{\A[a-z:][a-z0-9:./-]*\z}

      # Based on https://github.com/DataDog/datadog-agent/blob/45799c842bbd216bcda208737f9f11cade6fdd95/pkg/trace/traceutil/normalize.go#L131
      # Specifically:
      # - Must be valid UTF-8
      # - Invalid characters are replaced with an underscore
      # - Leading non-letter characters are removed but colons are kept
      # - Trailing non-letter characters are removed
      # - Trailing underscores are removed
      # - Consecutive underscores are merged into a single underscore
      # - Maximum length is 200 characters
      # If it's a tag value, allow it to start with a digit
      def self.normalize(original_value, remove_digit_start_char: false)
        transformed_value = original_value.to_s.encode('UTF-8', invalid: :replace, undef: :replace)
        transformed_value.strip!
        return "" if transformed_value.empty?

        return transformed_value if transformed_value.bytesize <= MAX_BYTE_SIZE &&
          transformed_value.match?(VALID_ASCII_TAG)

        if transformed_value.ascii_only? && transformed_value.length <= MAX_BYTE_SIZE
          normalized_value = transformed_value
        else
          byte_position = 0
          character_count = 0
          normalized_value = String.new(encoding: 'UTF-8')

          transformed_value.each_char do |char|
            byte_width = char.bytesize
            break if byte_position + byte_width > MAX_BYTE_SIZE
            break if character_count >= MAX_BYTE_SIZE

            normalized_value << char
            byte_position += byte_width
            character_count += 1
          end
        end

        normalized_value.downcase!
        normalized_value.gsub!(INVALID_TAG_CHARACTERS, '_')

        # The Trace Agent allows tag values to start with a number so this logic is here too
        leading_invalid_regex = remove_digit_start_char ? LEADING_INVALID_CHARS_NO_DIGITS : LEADING_INVALID_CHARS_WITH_DIGITS
        normalized_value.sub!(leading_invalid_regex, "")

        normalized_value.squeeze!('_') if normalized_value.include?('__')
        normalized_value.sub!(TRAILING_UNDERSCORES, "")

        normalized_value
      end
    end
  end
end
