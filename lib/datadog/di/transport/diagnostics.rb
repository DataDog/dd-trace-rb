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
        class EncodedParcel
          include Datadog::Core::Transport::Parcel
        end

        class Request < Datadog::Core::Transport::Request
        end

        class Transport < Core::Transport::Transport
          def send_diagnostics(payload)
            # TODO use transport encoder functionality?
            json = JSON.dump(payload)
            parcel = EncodedParcel.new(json)
            request = Request.new(parcel)

            client.send_request(:diagnostics, request)
          end
        end
      end
    end
  end
end
