# frozen_string_literal: true

require 'stringio'
require 'datadog/core/utils/base64'

module Datadog
  module Tracing
    module DataStreams
      # Represents a pathway context for data streams monitoring
      class PathwayContext
        attr_accessor :hash,
          :pathway_start_sec,
          :current_edge_start_sec,
          :parent_hash,
          :previous_direction,
          :closest_opposite_direction_hash,
          :closest_opposite_direction_edge_start

        def initialize(hash_value:, pathway_start_sec:, current_edge_start_sec:)
          @hash = hash_value
          @pathway_start_sec = pathway_start_sec
          @current_edge_start_sec = current_edge_start_sec
          @parent_hash = nil

          @previous_direction = ''
          @closest_opposite_direction_hash = 0
          @closest_opposite_direction_edge_start = current_edge_start_sec
        end

        def encode
          # Format:
          # - 8 bytes: hash value (little-endian)
          # - VarInt: pathway start time (milliseconds)
          # - VarInt: current edge start time (milliseconds)
          [@hash].pack('Q') <<
            encode_var_int_64((@pathway_start_sec * 1000).to_i) <<
            encode_var_int_64((@current_edge_start_sec * 1000).to_i)
        end

        def encode_b64
          Core::Utils::Base64.strict_encode64(encode)
        end

        # Decode pathway context from base64 encoded string
        def self.decode_b64(encoded_ctx)
          return nil unless encoded_ctx && !encoded_ctx.empty?

          begin
            binary_data = Core::Utils::Base64.strict_decode64(encoded_ctx)
            decode(binary_data)
          rescue
            # Invalid base64 or decode error
            nil
          end
        end

        # Decode pathway context from binary data
        def self.decode(binary_data)
          return nil unless binary_data && binary_data.bytesize >= 8

          reader = StringIO.new(binary_data)

          # Extract 8-byte hash (little-endian)
          hash_bytes = reader.read(8)
          return nil unless hash_bytes

          hash_value = hash_bytes.unpack1('Q')

          # Extract pathway start time (VarInt milliseconds)
          pathway_start_ms = decode_varint(reader)
          return nil unless pathway_start_ms

          # Extract current edge start time (VarInt milliseconds)
          current_edge_start_ms = decode_varint(reader)
          return nil unless current_edge_start_ms

          # Convert milliseconds to seconds
          pathway_start_sec = pathway_start_ms / 1000.0
          current_edge_start_sec = current_edge_start_ms / 1000.0

          new(
            hash_value: hash_value,
            pathway_start_sec: pathway_start_sec,
            current_edge_start_sec: current_edge_start_sec
          )
        rescue EOFError
          # Not enough data in binary stream
          nil
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

        # Decode VarInt from IO stream using Ruby-idiomatic approach
        #
        # VarInt format: Each byte uses 7 bits for data, 1 bit for continuation
        # - High bit set = more bytes follow
        # - High bit clear = final byte
        # - Data bits accumulated in little-endian order
        def self.decode_varint(io)
          value = 0
          shift = 0

          loop do
            byte = io.readbyte

            # Add this byte's 7 data bits to our value
            value |= (byte & 0x7F) << shift

            # If high bit is clear, we're done
            return value unless (byte & 0x80).nonzero?

            shift += 7

            # Safety: prevent infinite decoding
            raise EOFError if shift >= 64
          end
        rescue EOFError
          nil
        end
        private_class_method :decode_varint
      end
    end
  end
end
