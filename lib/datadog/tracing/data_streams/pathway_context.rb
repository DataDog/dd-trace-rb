# frozen_string_literal: true

require 'base64'

module Datadog
  module Tracing
    module DataStreams
      # Represents a pathway context for data streams monitoring
      class PathwayContext
        def initialize(hash_value, pathway_start_sec, current_edge_start_sec)
          @hash = hash_value
          @pathway_start_sec = pathway_start_sec
          @current_edge_start_sec = current_edge_start_sec
        end

        def encode
          # Format:
          # - 8 bytes: hash value (little-endian)
          # - VarInt: pathway start time (milliseconds)
          # - VarInt: current edge start time (milliseconds)
          [
            [@hash].pack('Q<'),
            encode_var_int_64((@pathway_start_sec * 1000).to_i),
            encode_var_int_64((@current_edge_start_sec * 1000).to_i)
          ].join
        end

        def encode_b64
          Base64.strict_encode64(encode)
        end

        private

        def encode_var_int_64(value)
          bytes = []
          while value >= 0x80
            bytes << ((value & 0x7F) | 0x80)
            value >>= 7
          end
          bytes << value
          bytes.pack('C*')
        end
      end
    end
  end
end

