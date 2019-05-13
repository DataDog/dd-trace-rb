require 'ddtrace/configuration'
require 'ddtrace/span'
require 'ddtrace/ext/distributed'

module Datadog
  module DistributedTracing
    module Headers
      # Headers provides easy access and validation methods for Rack headers
      class Headers
        include Ext::DistributedTracing

        def initialize(env)
          @env = env
        end

        def header(name)
          rack_header = "http-#{name}".upcase!.tr('-', '_')

          hdr = @env[rack_header]

          # Only return the value if it is not an empty string
          hdr if hdr != ''
        end

        def id(hdr, base = 10)
          value_to_id(header(hdr), base)
        end

        def value_to_id(value, base = 10)
          id = value_to_number(value, base)

          # Return early if we could not parse a number
          return if id.nil?

          # Zero or greater than max allowed value of 2**64
          return if id.zero? || id > Span::EXTERNAL_MAX_ID
          id < 0 ? id + (2**64) : id
        end

        def number(hdr, base = 10)
          value_to_number(header(hdr), base)
        end

        def value_to_number(value, base = 10)
          # It's important to make a difference between no header,
          # and a header defined to zero.
          return if value.nil?

          # Be sure we have a string
          value = value.to_s

          if base == 16
            # Lowercase if we want to parse base16 e.g. 3E8 => 3e8
            # DEV: Ruby will parse `3E8` just fine, but to test
            #      `num.to_s(base) == value` we need to lowercase
            value = value.downcase

            # Truncate to trailing 16 characters if length is greater than 16
            # https://github.com/apache/incubator-zipkin/blob/21fe362899fef5c593370466bc5707d3837070c2/zipkin/src/main/java/zipkin2/storage/StorageComponent.java#L49-L53
            # DEV: This ensures we truncate B3 128-bit trace and span ids to 64-bit
            value = value[value.length-16, 16] if value.length > 16

            # Remove any leading zeros
            # DEV: When we call `num.to_s(16)` later Ruby will not add leading zeros
            #      for us so we want to make sure the comparision will work as expected
            # DEV: regex, remove all leading zeros up until we find the last 0 in the string
            #      or we find the first non-zero, this allows `'0000' -> '0'` and `'00001' -> '1'`
            value = value.sub(/^0*(?=(0$)|[^0])/, '')
          end

          # Convert header to an integer
          # DEV: Ruby `.to_i` will return `0` if a number could not be parsed
          num = value.to_i(base)

          # Ensure the parsed number is the same as the original string value
          # e.g. We want to make sure to throw away `'nan'.to_i == 0`
          return unless num.to_s(base) == value

          num
        end
      end
    end
  end
end
