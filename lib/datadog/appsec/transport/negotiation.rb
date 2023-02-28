# typed: false

require_relative '../../../ddtrace/transport/request'

module Datadog
  module AppSec
    module Transport
      module Negotiation
        # Negotiation request
        class Request < Datadog::Transport::Request
        end

        # Negotiation response
        module Response
          attr_reader :version, :endpoints, :config
        end

        class Transport
          attr_reader :client, :apis, :default_api, :current_api_id

          def initialize(apis, default_api)
            @apis = apis

            @client = HTTP::Client.new(current_api)
          end

          def send_info
            request = Request.new

            response = @client.send_info_payload(request)

            # TODO: not sure if we're supposed to do that as we don't chunk like traces
            # Datadog.health_metrics.transport_chunked(responses.size)

            response
          end

          def current_api
            @apis[HTTP::API::ROOT]
          end
        end
      end
    end
  end
end
