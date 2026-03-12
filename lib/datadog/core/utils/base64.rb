# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Helper methods for encoding and decoding base64
      module Base64
        def self.encode64(bin)
          [bin].pack('m')
        end

        def self.strict_encode64(bin)
          [bin].pack('m0')
        end

        def self.strict_decode64(str)
          # The 'm0' format always returns a String, but String#unpack1's RBS
          # signature is too broad (Integer | Float | String | nil) for Steep
          # to verify this statically.
          str.unpack1('m0') #: String
        end
      end
    end
  end
end
