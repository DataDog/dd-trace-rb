# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Base64 encoding/decoding without using the `base64` gem,
      # which is no longer a default gem since Ruby 3.4.
      module Base64Codec
        def self.encode64(bin)
          [bin].pack("m")
        end

        def self.strict_encode64(bin)
          [bin].pack("m0")
        end

        def self.strict_decode64(str)
          str.unpack1("m0") #: String # 'm0' format always returns a String
        end
      end
    end
  end
end
