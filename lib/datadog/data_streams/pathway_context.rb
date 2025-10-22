# frozen_string_literal: true

require 'stringio'
require_relative '../core/utils/base64'

module Datadog
  module DataStreams
    # Represents a pathway context for data streams monitoring
    class PathwayContext
      # The current pathway hash
      attr_accessor :hash
      # When the pathway started
      attr_accessor :pathway_start
      # When the current edge started
      attr_accessor :current_edge_start
      # The hash of the parent checkpoint
      attr_accessor :parent_hash
      # The direction tag of the previous checkpoint (e.g., 'direction:in', 'direction:out'), or nil if none
      attr_accessor :previous_direction
      # Hash of the closest checkpoint in opposite direction (used for loop detection)
      attr_accessor :closest_opposite_direction_hash
      # Edge start time of the closest opposite direction checkpoint
      attr_accessor :closest_opposite_direction_edge_start

      def initialize(hash_value:, pathway_start:, current_edge_start:)
        @hash = hash_value
        @pathway_start = pathway_start
        @current_edge_start = current_edge_start
        @parent_hash = nil

        @previous_direction = nil
        @closest_opposite_direction_hash = 0
        @closest_opposite_direction_edge_start = current_edge_start
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

      private

      def encode
        # Format:
        # - 8 bytes: hash value (little-endian)
        # - VarInt: pathway start time (milliseconds)
        # - VarInt: current edge start time (milliseconds)
        [@hash].pack('Q') <<
          encode_var_int_64(time_to_ms(@pathway_start)) <<
          encode_var_int_64(time_to_ms(@current_edge_start))
      end

      # Decode pathway context from binary data
      def self.decode(binary_data)
        return nil unless binary_data && binary_data.bytesize >= 8

        reader = StringIO.new(binary_data)

        # Extract 8-byte hash (little-endian)
        hash_bytes = reader.read(8)
        return nil unless hash_bytes

        hash_value = hash_bytes.unpack1('Q') # : Integer

        # Extract pathway start time (VarInt milliseconds)
        pathway_start_ms = decode_varint(reader)
        return nil unless pathway_start_ms

        # Extract current edge start time (VarInt milliseconds)
        current_edge_start_ms = decode_varint(reader)
        return nil unless current_edge_start_ms

        # Convert milliseconds to Time objects
        pathway_start = ms_to_time(pathway_start_ms)
        current_edge_start = ms_to_time(current_edge_start_ms)

        new(
          hash_value: hash_value,
          pathway_start: pathway_start,
          current_edge_start: current_edge_start
        )
      rescue EOFError
        # Not enough data in binary stream
        nil
      end
      private_class_method :decode

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

      def self.ms_to_time(milliseconds)
        ::Time.at(milliseconds / 1000.0)
      end
      private_class_method :ms_to_time

      def time_to_ms(time)
        (time.to_f * 1000).to_i
      end
    end
  end
end
