# frozen_string_literal: true

module Datadog
  module Core
    module Normalizer
      module_function

      INVALID_TAG_CHARACTERS = %r{[^\p{L}0-9_\-:./]}
      LEADING_INVALID_CHARS = %r{\A[^\p{L}:]+}
      TRAILING_UNDERSCORES = %r{_+\z}
      MAX_CHARACTER_LENGTH = 200

      # Based on https://github.com/DataDog/datadog-agent/blob/45799c842bbd216bcda208737f9f11cade6fdd95/pkg/trace/traceutil/normalize.go#L131
      # Specifically:
      # - Must be valid UTF-8
      # - Invalid characters are replaced with an underscore
      # - Leading non-letter characters are removed but colons are kept
      # - Trailing non-letter characters are removed
      # - Trailing underscores are removed
      # - Consecutive underscores are merged into a single underscore
      # - Maximum length is 200 characters
      def self.normalize(original_value)
        normalized_value = original_value.to_s.encode('UTF-8', invalid: :replace, undef: :replace).strip
        return "" if normalized_value.empty?

        normalized_value.downcase!
        normalized_value.gsub!(INVALID_TAG_CHARACTERS, '_')
        normalized_value.sub!(LEADING_INVALID_CHARS, "")
        normalized_value.sub!(TRAILING_UNDERSCORES, "")
        normalized_value.squeeze!('_') if normalized_value.include?('__')
        normalized_value.slice!(MAX_CHARACTER_LENGTH..-1) if normalized_value.length > MAX_CHARACTER_LENGTH

        normalized_value
      end
    end
  end
end
