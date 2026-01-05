# frozen_string_literal: true

require_relative '../../transport/parcel'
require_relative '../../transport/transport'
require_relative 'http/telemetry'

module Datadog
  module Core
    module Telemetry
      module Transport
        module Telemetry
          class EncodedParcel
            include Datadog::Core::Transport::Parcel
          end

          class Request < Datadog::Core::Transport::Request
            attr_reader :request_type
            attr_reader :api_key

            def initialize(request_type, parcel, api_key)
              @request_type = request_type
              super(parcel)
              @api_key = api_key
            end
          end

          class Transport < Core::Transport::Transport
            attr_accessor :api_key

            def send_telemetry(request_type:, payload:)
              json = JSON.dump(payload)
              parcel = EncodedParcel.new(json)
              request = Request.new(request_type, parcel, api_key)

              @client.send_request(:telemetry, request)
              # Perform no error checking here
            end
          end
        end
      end
    end
  end
end
