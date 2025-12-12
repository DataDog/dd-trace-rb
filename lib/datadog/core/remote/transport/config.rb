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
          # Data transfer object for encoded traces
          class EncodedParcel
            include Datadog::Core::Transport::Parcel

            def count
              data.length
            end
          end

          # Config request
          class Request < Datadog::Core::Transport::Request
          end

          # Config transport
          class Transport < Core::Transport::Transport
            def send_config(payload)
              json = JSON.dump(payload)
              parcel = EncodedParcel.new(json)
              request = Request.new(parcel)

              @client.send_request(:config, request)
            end
          end
        end
      end
    end
  end
end
