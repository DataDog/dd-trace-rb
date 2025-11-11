# frozen_string_literal: true

module Datadog
  module Core
    module Normalizer
      module_function

      INVALID_TAG_CHARACTERS = %r{[^a-z0-9_\-:./]}.freeze

      # Based on https://docs.datadoghq.com/getting_started/tagging/#defining-tags
      # Currently a reimplementation of the logic in the
      # Datadog::Tracing::Metadata::Ext::HTTP::Headers.to_tag method with some additional items
      # TODO: Swap out the logic in the Datadog Tracing Metadata headers logic
      def self.normalize(original_value)
        return "" if original_value.nil? || original_value.to_s.strip.empty?

        # Removes whitespaces
        normalized_value = original_value.to_s.strip
        # Lower case characters
        normalized_value.downcase!
        # Invalid characters are replaced with an underscore
        normalized_value.gsub!(INVALID_TAG_CHARACTERS, '_')
        # Merge consecutive underscores with a single underscore
        normalized_value.squeeze!('_')
        # Remove leading non-letter characters
        normalized_value.sub!(/\A[^a-z]+/, "")
        # Maximum length is 200 characters
        normalized_value = normalized_value[0...200] if normalized_value.length > 200

        normalized_value
      end
    end
  end
end
