# frozen_string_literal: true

require 'ddtrace/configuration'
require 'ddtrace/span'
require 'ddtrace/ext/distributed'

module Datadog
  module DistributedTracing
    module Headers
      # Headers provides easy access and validation methods for headers
      class Headers
        include Ext::DistributedTracing

        def initialize(env)
          @env = env
        end

        def header(name)
          hdr = @env[name]

          # Only return the value if it is not an empty string
          hdr if hdr != ''
        end

        def id(hdr, base = 10)
          value_to_id(header(hdr), base)
        end

        def value_to_id(value, base = 10)
          id = value_to_number(value, base)

          # Return early if we could not parse a number
          return unless id

          # Zero or greater than max allowed value of 2**64
          return if id.zero? || id > Span::EXTERNAL_MAX_ID

          id < 0 ? id + Span::EXTERNAL_MAX_ID : id
        end

        def number(hdr, base = 10)
          value_to_number(header(hdr), base)
        end

        def value_to_number(value, base = 10)
          # It's important to make a difference between no header,
          # and a header defined to zero.
          return unless value

          # Be sure we have a string
          value = value.to_s

          # If we are parsing base16 number then truncate to 64-bit
          value = DistributedTracing::Headers::Helpers.truncate_base16_number(value) if base == 16

          # Convert header to an integer
          begin
            Integer(value, base)
          rescue ArgumentError
            nil
          end
        end
      end
    end
  end
end
