# frozen_string_literal: true

require_relative '../../transport/parcel'
require_relative 'http/client'

module Datadog
  module Core
    module Telemetry
      module Transport
        module Telemetry
          class EncodedParcel
            include Datadog::Core::Transport::Parcel
          end

          class Request < Datadog::Core::Transport::Request
          end

          class Transport
            attr_reader :client, :apis, :default_api, :current_api_id, :logger

            def initialize(apis, default_api, logger:)
              @apis = apis
              @logger = logger

              @client = HTTP::Client.new(current_api, logger: logger)
            end

            def current_api
              @apis[HTTP::API::TELEMETRY]
            end

            def send_telemetry(payload)
              json = JSON.dump(payload)
              parcel = EncodedParcel.new(json)
              request = Request.new(parcel)

              response = @client.send_telemetry_payload(request)
              # Perform no error checking here
            end
          end
        end
      end
    end
  end
end
