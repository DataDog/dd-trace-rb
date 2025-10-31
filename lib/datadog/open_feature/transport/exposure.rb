# frozen_string_literal: true

require_relative '../../core/transport/parcel'
require_relative '../../core/transport/request'
require_relative 'http/client'
require_relative 'http/exposures'

module Datadog
  module OpenFeature
    module Transport
      module Exposure
        class EncodedParcel
          include Datadog::Core::Transport::Parcel

          def encode_with(encoder)
            encoder.encode(data)
          end
        end

        class Request < Datadog::Core::Transport::Request
          attr_reader :headers

          def initialize(parcel, headers = {})
            super(parcel)
            @headers = headers
          end
        end

        class Transport
          attr_reader :client, :apis, :default_api, :logger

          def initialize(apis, default_api, logger: Datadog.logger)
            @apis = apis
            @default_api = default_api
            @logger = logger

            @client = HTTP::Client.new(@apis[default_api], logger: logger)
          end

          def send_exposures(payload, headers: {})
            parcel = EncodedParcel.new(payload)
            request = Request.new(parcel, headers)

            client.send_exposures(request)
          end
        end
      end
    end
  end
end
