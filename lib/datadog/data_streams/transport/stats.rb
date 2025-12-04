# frozen_string_literal: true

require 'msgpack'
require 'zlib'
require_relative '../../core/transport/parcel'
require_relative '../../core/transport/request'
require_relative '../../core/transport/transport'

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
        class Transport < Core::Transport::Transport
          def send_stats(payload)
            # MessagePack encode and gzip compress the payload
            msgpack_data = MessagePack.pack(payload)
            compressed_data = Zlib.gzip(msgpack_data)

            # Create parcel and request
            parcel = EncodedParcel.new(compressed_data)
            request = Request.new(parcel)

            # Send to agent
            client.send_request(:stats, request)
          end
        end
      end
    end
  end
end
