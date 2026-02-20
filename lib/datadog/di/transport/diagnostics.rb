# frozen_string_literal: true

require 'json'

require_relative '../../core/transport/parcel'
require_relative '../../core/transport/request'
require_relative '../../core/transport/transport'
require_relative 'http/diagnostics'

module Datadog
  module DI
    module Transport
      module Diagnostics
        class Request < Datadog::Core::Transport::Request
        end

        class Transport < Core::Transport::Transport
          def send_diagnostics(payload)
            encoder = Core::Encoding::JSONEncoder
            parcel = Core::Transport::Parcel.new(
              encoder.encode(payload),
              content_type: encoder.content_type,
            )
            request = Request.new(parcel)

            client.send_request(:diagnostics, request)
          end
        end
      end
    end
  end
end
