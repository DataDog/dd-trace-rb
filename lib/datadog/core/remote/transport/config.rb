# frozen_string_literal: true

require_relative '../../../core/transport/request'
require_relative '../../../core/transport/parcel'
require_relative '../../../core/transport/transport'
require_relative 'http/config'

module Datadog
  module Core
    module Remote
      module Transport
        module Config
          # Config request
          class Request < Datadog::Core::Transport::Request
          end

          # Config transport
          class Transport < Core::Transport::Transport
            def send_config(payload)
              encoder = Core::Encoding::JSONEncoder
              parcel = Core::Transport::Parcel.new(
                encoder.encode(payload),
                content_type: encoder.content_type,
              )
              request = Request.new(parcel)

              @client.send_request(:config, request)
            end
          end
        end
      end
    end
  end
end
