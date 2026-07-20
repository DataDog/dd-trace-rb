# frozen_string_literal: true

require 'digest'

module Datadog
  module OpenFeature
    module Hooks
      class SpanEnrichmentHook
        # Encoding/crypto helpers implementing the fixed cross-SDK wire format.
        module Codec
          module_function

          # ULEB128 stores 7 bits per byte; the high bit flags that more bytes follow.
          LOW_7_BITS_MASK = 0x7F
          CONTINUATION_BIT = 0x80

          # The `bytes` buffer built below MUST be binary (ASCII-8BIT): `String#<<`
          # with an Integer on a UTF-8 string appends a Unicode *codepoint*, so any
          # byte >= 0x80 would be re-encoded as a 2-byte UTF-8 sequence and corrupt
          # the varint (e.g. serial 2312 -> bytes 88 12, but UTF-8 would emit
          # C2 88 12 = 296002 on decode). `(+'').b` gives a mutable binary string.
          def encode_varint(value)
            bytes = (+'').b
            while value > LOW_7_BITS_MASK
              bytes << ((value & LOW_7_BITS_MASK) | CONTINUATION_BIT)
              value >>= 7
            end
            bytes << (value & LOW_7_BITS_MASK)
            bytes
          end

          # Encode a Set of serial ids as base64(ULEB128 delta-varint).
          # Empty set -> empty string (the caller omits the tag).
          def encode_delta_varint(serial_ids)
            sorted = serial_ids.to_a.sort
            return '' if sorted.empty?

            bytes = (+'').b
            prev = 0
            sorted.each do |id|
              bytes << encode_varint(id - prev)
              prev = id
            end
            # `pack('m0')` is RFC 4648 base64 with no newlines (== strict_encode64)
            # and needs no `base64` gem, which stopped being a default gem in Ruby 3.4.
            [bytes].pack('m0')
          end

          # Lowercase hex SHA256 of the targeting key: it is hashed before
          # emission so raw user identifiers never leave the process.
          def hash_targeting_key(targeting_key)
            Digest::SHA256.hexdigest(targeting_key)
          end
        end
      end
    end
  end
end
