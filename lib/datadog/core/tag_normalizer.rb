# frozen_string_literal: true

require_relative 'utils'

module Datadog
  module Core
    # @api private
    module TagNormalizer
      # Normalization logic used for tag keys and values that the Trace Agent has for traces
      # Useful for ensuring that tag keys and values are normalized consistently
      # An use case for now is Process Tags which need to be sent across various intakes (profiling, tracing, etc.) consistently

      module_function

      INVALID_TAG_CHARACTERS = %r{[^\p{L}0-9_\-:./]}
      LEADING_INVALID_CHARS_NO_DIGITS = %r{\A[^\p{L}:]++}
      LEADING_INVALID_CHARS_WITH_DIGITS = %r{\A[^\p{L}0-9:./]++}
      MAX_BYTE_SIZE = 200 # Represents the max tag length
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
      # @param original_value [String] The original string
      # @param remove_digit_start_char [Boolean] - whether to remove the leading digit (currently only used for tag values)
      # @return [String] The normalized string
      def self.normalize(original_value, remove_digit_start_char: false)
        transformed_value = Utils.utf8_encode(original_value, replace_invalid: true)
        transformed_value.strip!
        return "" if transformed_value.empty?

        return transformed_value if transformed_value.bytesize <= MAX_BYTE_SIZE &&
          transformed_value.match?(VALID_ASCII_TAG)

        normalized_value = transformed_value

        if normalized_value.bytesize > MAX_BYTE_SIZE
          normalized_value = normalized_value.byteslice(0, MAX_BYTE_SIZE)
          normalized_value.scrub!("")
        end

        normalized_value.downcase!
        normalized_value.gsub!(INVALID_TAG_CHARACTERS, '_')

        # The Trace Agent allows tag values to start with a number so this logic is here too
        leading_invalid_regex = remove_digit_start_char ? LEADING_INVALID_CHARS_NO_DIGITS : LEADING_INVALID_CHARS_WITH_DIGITS
        normalized_value.sub!(leading_invalid_regex, "")

        normalized_value.squeeze!('_') if normalized_value.include?('__')
        normalized_value.delete_suffix!('_')

        normalized_value
      end
    end
  end
end
