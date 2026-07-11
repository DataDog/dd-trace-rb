# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Helper methods for parsing string values into Numeric
      module Duration
        def self.call(value, base: :s)
          is_float = value.include?('.')

          scale = case base
          when :s
            1_000_000_000
          when :ms
            1_000_000
          when :us
            1000
          when :ns
            1
          else
            raise ArgumentError, "invalid base: #{base.inspect}"
          end

          result = case value
          when /^(\d+(?:\.\d+)?)h$/
            cast(Regexp.last_match(1), is_float) * 1_000_000_000 * 60 * 60 / scale
          when /^(\d+(?:\.\d+)?)m$/
            cast(Regexp.last_match(1), is_float) * 1_000_000_000 * 60 / scale
          when /^(\d+(?:\.\d+)?)s$/
            cast(Regexp.last_match(1), is_float) * 1_000_000_000 / scale
          when /^(\d+(?:\.\d+)?)ms$/
            cast(Regexp.last_match(1), is_float) * 1_000_000 / scale
          when /^(\d+(?:\.\d+)?)us$/
            cast(Regexp.last_match(1), is_float) * 1_000 / scale
          when /^(\d+(?:\.\d+)?)ns$/
            cast(Regexp.last_match(1), is_float) / scale
          when /^(\d+(?:\.\d+)?)$/
            cast(Regexp.last_match(1), is_float)
          else
            raise ArgumentError, "invalid duration: #{value.inspect}"
          end

          result.round
        end

        def self.cast(str, is_float)
          is_float ? Float(str) : Integer(str)
        end
        private_class_method :cast
      end
    end
  end
end
