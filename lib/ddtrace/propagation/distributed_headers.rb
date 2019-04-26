require 'ddtrace/configuration'
require 'ddtrace/span'
require 'ddtrace/ext/distributed'

module Datadog
  # DistributedHeaders provides easy access and validation to headers
  class DistributedHeaders
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
      # DEV: Convert to a string first in case we were given a non-string
      value = value.to_s.to_i(base)

      # Zero or greater than max allowed value of 2**64
      return if value.zero? || value > Span::EXTERNAL_MAX_ID
      value < 0 ? value + 0x1_0000_0000_0000_0000 : value
    end

    def number(hdr)
      value_to_number(header(hdr))
    end

    def value_to_number(hdr)
      # It's important to make a difference between no header,
      # and a header defined to zero.
      return if hdr.nil?

      # Convert header to an integer
      value = hdr.to_i

      # Ensure the parsed number is the same as the original string value
      # e.g. We want to make sure to throw away `'nan'.to_i == 0`
      # DEV: Ruby `.to_i` will return `0` if a number could not be parsed
      return unless value.to_s == hdr.to_s

      value
    end
  end
end
