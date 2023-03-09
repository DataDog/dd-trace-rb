# frozen_string_literal: true

require_relative '../../../ddtrace/transport/request'
require_relative '../../../ddtrace/transport/parcel'

module Datadog
  module Core
    module Transport
      module Config
        # Data transfer object for encoded traces
        class EncodedParcel
          include Datadog::Transport::Parcel

          def initialize(data)
            super(data)
          end

          def count
            data.length
          end
        end

        # Config request
        class Request < Datadog::Transport::Request
        end

        # Config response
        module Response
          attr_reader :roots, :targets, :target_files, :client_configs
        end

        class Transport
          attr_reader :client, :apis, :default_api, :current_api_id

          def initialize(apis, default_api)
            @apis = apis

            @client = HTTP::Client.new(current_api)

            # TODO: this should go in the high level remote config client
            @client_id = SecureRandom.uuid
          end

          ##### there is only one transport! it's negotiation!
          def send_config(payload)
            json = JSON.dump(payload)
            parcel = EncodedParcel.new(json)
            request = Request.new(parcel)

            response = @client.send_config_payload(request)

            # TODO: not sure if we're supposed to do that as we don't chunk like traces
            # Datadog.health_metrics.transport_chunked(responses.size)

            response
          end

          def current_api
            @apis[HTTP::API::V7]
          end
        end
      end
    end
  end
end
