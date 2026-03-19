# frozen_string_literal: true

require 'msgpack'
require_relative '../../../core/transport/parcel'
require_relative '../../../core/transport/request'
require_relative '../../../core/transport/transport'

module Datadog
  module Tracing
    module Stats
      module Transport
        # Transport module for client-side trace stats
        module StatsTransport
          # Request for trace stats
          class Request < Datadog::Core::Transport::Request
          end

          # Transport for sending client-side trace stats to the agent
          class Transport < Core::Transport::Transport
            def send_stats(payload)
              # MessagePack encode the payload
              msgpack_data = MessagePack.pack(payload)

              # Create parcel and request
              parcel = Core::Transport::Parcel.new(
                msgpack_data,
                content_type: 'application/msgpack',
              )
              request = Request.new(parcel)

              # Send to agent
              client.send_request(:stats, request)
            end
          end
        end
      end
    end
  end
end
