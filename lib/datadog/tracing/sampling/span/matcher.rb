# frozen_string_literal: true

module Datadog
  module Tracing
    module Sampling
      module Span
        # Checks if a span conforms to a matching criteria.
        class Matcher
          attr_reader :name, :service

          # Pattern that matches any string
          MATCH_ALL_PATTERN = '*'

          # Matches span name and service to their respective patterns provided.
          #
          # The patterns are {String}s with two special characters available:
          # 1. `?`: matches exactly one of any character.
          # 2. `*`: matches a substring of any size, including zero.
          # These patterns can occur any point of the string, any number of times.
          #
          # Both {SpanOperation#name} and {SpanOperation#service} must match the provided patterns.
          #
          # The whole String has to match the provided patterns: providing a pattern that
          # matches a portion of the provided String is not considered a match.
          #
          # @example web-*
          #   `'web-*'` will match any string starting with `web-`.
          # @example cache-?
          #   `'cache-?'` will match any string starting with `database-` followed by exactly one character.
          #
          # @param name_pattern [String] a pattern to be matched against {SpanOperation#name}
          # @param service_pattern [String] a pattern to be matched against {SpanOperation#service}
          def initialize(name_pattern: MATCH_ALL_PATTERN, service_pattern: MATCH_ALL_PATTERN)
            @name = pattern_to_regex(name_pattern)
            @service = pattern_to_regex(service_pattern)
          end

          # Returns `true` if the span conforms to the configured patterns,
          # `false` otherwise
          #
          # @param [SpanOperation] span
          # @return [Boolean]
          def match?(span)
            # Matching is performed at the end of the lifecycle of a Span,
            # thus both `name` and `service` are guaranteed to be not `nil`.
            @name.match?(span.name) && @service.match?(span.service)
          end

          def ==(other)
            return super unless other.is_a?(Matcher)

            name == other.name &&
              service == other.service
          end

          private

          # @param pattern [String]
          # @return [Regexp]
          def pattern_to_regex(pattern)
            # Ensure no undesired characters are treated as regex.
            # Our valid special characters, `?` and `*`,
            # will be escaped so...
            pattern = Regexp.quote(pattern)

            # ...we account for that here:
            pattern.gsub!('\?', '.') # Any single character
            pattern.gsub!('\*', '.*') # Any substring

            # Patterns have to match the whole input string
            pattern = "\\A#{pattern}\\z"

            Regexp.new(pattern)
          end
        end
      end
    end
  end
end
