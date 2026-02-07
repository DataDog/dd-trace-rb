# frozen_string_literal: true

module Datadog
  module Core
    module Transport
      # Data transfer object for transporting already-encoded data.
      #
      # A Parcel is a container that holds pre-encoded data along with metadata
      # about its encoding. The key design principle is that encoding happens
      # BEFORE the Parcel is created, not inside it.
      #
      # @example Creating a Parcel with JSON data
      #   encoder = Core::Encoding::JSONEncoder
      #   parcel = Parcel.new(
      #     encoder.encode(payload),
      #     content_type: encoder.content_type
      #   )
      #
      # @example Creating a Parcel with compressed MessagePack data
      #   msgpack_data = MessagePack.pack(payload)
      #   compressed_data = Zlib.gzip(msgpack_data)
      #   parcel = Parcel.new(
      #     compressed_data,
      #     content_type: 'application/msgpack',
      #     content_encoding: 'gzip'
      #   )
      #
      # @example Accessing Parcel data in HTTP transport
      #   # In HTTP adapters, Parcel metadata maps to HTTP headers:
      #   env.headers['Content-Type'] = request.parcel.content_type
      #   env.headers['Content-Encoding'] = request.parcel.content_encoding
      #   env.body = request.parcel.data
      #
      # The content_type and content_encoding fields are optional but recommended:
      # - Set them when creating the Parcel for automatic header management
      # - Leave them nil for IO transports or when headers are managed elsewhere
      # - HTTP transports use these to set appropriate request headers
      #
      # @see Core::Encoding::JSONEncoder for JSON encoding utilities
      # @see Core::Transport::Request which wraps Parcels for transmission
      class Parcel
        # Creates a new Parcel with pre-encoded data.
        #
        # @param data [String] The already-encoded data (e.g., JSON string, MessagePack bytes)
        # @param content_type [String, nil] MIME type of the data (e.g., 'application/json')
        # @param content_encoding [String, nil] Encoding applied to data (e.g., 'gzip')
        def initialize(data, content_type: nil, content_encoding: nil)
          @data = data
          @content_type = content_type
          @content_encoding = content_encoding
        end

        # @!attribute [r] data
        #   @return [String] The encoded data payload
        attr_reader :data

        # Returns the length of the encoded data.
        #
        # @return [Integer] Number of bytes in the data
        def length
          data.length
        end

        # @!attribute [r] content_type
        #   @return [String, nil] MIME type of the data (e.g., 'application/json')
        attr_reader :content_type

        # @!attribute [r] content_encoding
        #   @return [String, nil] Encoding applied to data (e.g., 'gzip')
        attr_reader :content_encoding
      end
    end
  end
end
