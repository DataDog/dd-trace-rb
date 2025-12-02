# frozen_string_literal: true

require 'msgpack'
require 'zlib'
require_relative '../../core/transport/parcel'
require_relative '../../core/transport/request'

module Datadog
  module DataStreams
    module Transport
      module Stats
        # Parcel for encoded DSM stats payload
        class EncodedParcel
          include Datadog::Core::Transport::Parcel

          def initialize(data)
            @data = data
          end

          attr_reader :data
        end

        # Request for DSM stats
        class Request < Datadog::Core::Transport::Request
        end

        # Transport for Data Streams Monitoring stats
        class Transport
          attr_reader :client, :apis, :current_api_id, :logger

          def initialize(apis, default_api, logger:)
            @apis = apis
            @logger = logger
            @default_api = default_api
            @current_api_id = default_api

            @client = DataStreams::Transport::HTTP::Client.new(current_api, logger: @logger)
          end

          def send_stats(payload)
            # MessagePack encode and gzip compress the payload
            msgpack_data = MessagePack.pack(payload)
            compressed_data = Zlib.gzip(msgpack_data)

            # Create parcel and request
            parcel = EncodedParcel.new(compressed_data)
            request = Request.new(parcel)

            # Send to agent
            client.send_stats_payload(request)
          end

          def current_api
            apis[@current_api_id]
          end
        end
      end
    end
  end
end
