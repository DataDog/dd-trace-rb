# frozen_string_literal: true

require_relative '../sampling/ext'
require_relative '../utils'

module Datadog
  module Tracing
    module Distributed
      # Helpers module provides common helper functions for distributed tracing data
      module Helpers
        # Base provides common methods for distributed helper classes
        def self.clamp_sampling_priority(sampling_priority)
          # B3 doesn't have our -1 (USER_REJECT) and 2 (USER_KEEP) priorities so convert to acceptable 0/1
          if sampling_priority < 0
            sampling_priority = Sampling::Ext::Priority::AUTO_REJECT
          elsif sampling_priority > 1
            sampling_priority = Sampling::Ext::Priority::AUTO_KEEP
          end

          sampling_priority
        end

        # def self.format_base16_number(value)
        #   # Lowercase if we want to parse base16 e.g. 3E8 => 3e8
        #   # DEV: Ruby will parse `3E8` just fine, but to test
        #   #      `num.to_s(base) == value` we need to lowercase
        #   value = value.downcase

        #   # Remove any leading zeros
        #   # DEV: When we call `num.to_s(16)` later Ruby will not add leading zeros
        #   #      for us so we want to make sure the comparision will work as expected
        #   # DEV: regex, remove all leading zeros up until we find the last 0 in the string
        #   #      or we find the first non-zero, this allows `'0000' -> '0'` and `'00001' -> '1'`
        #   value.sub(/^0*(?=(0$)|[^0])/, '')
        # end

        # def self.value_to_id(value, base: 10)
        #   id = value_to_number(value, base: base)

        #   # Return early if we could not parse a number
        #   return if id.nil?

        #   # Zero or greater than max allowed value of 2**64
        #   return if id.zero? || id > Tracing::Utils::TraceId::MAX

        #   id < 0 ? id + (2**64) : id
        # end

        # def self.value_to_number(value, base: 10)
        #   # It's important to make a difference between no data and zero.
        #   return if value.nil?

        #   # Be sure we have a string
        #   value = value.to_s

        #   # If we are parsing base16 number then truncate to 64-bit
        #   value = Helpers.format_base16_number(value) if base == 16

        #   # Convert value to an integer
        #   # DEV: Ruby `.to_i` will return `0` if a number could not be parsed
        #   num = value.to_i(base)

        #   # Ensure the parsed number is the same as the original string value
        #   # e.g. We want to make sure to throw away `'nan'.to_i == 0`
        #   return unless num.to_s(base) == value

        #   num
        # end

        def self.parse_decimal_id(value)
          return unless value

          value = value.to_s
          num   = value.to_i

          return unless num.to_s(10) == value

          num
        end

        def self.parse_hex_id(value, length: nil)
          return unless value

          value = value.to_s.downcase
          value = value[value.length - length, length] if length && value.length > length
          value = value.sub(/^0*(?=(0$)|[^0])/, '')

          num = value.to_i(16)

          return unless num.to_s(16) == value

          num
        end
      end
    end
  end
end
