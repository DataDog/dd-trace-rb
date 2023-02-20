# typed: false

require 'json'

require_relative '../traces'
require_relative 'client'
require_relative 'response'
require_relative 'api/endpoint'
require_relative 'api/instance'

module Datadog
  module AppSec
    module Transport
      module HTTP
        # HTTP transport behavior for remote configuration
        module RemoteConfiguration
          # Response from HTTP transport for remote configuration
          class Response
            include HTTP::Response
            include Datadog::Transport::RemoteConfiguration::Response

            def initialize(http_response, options = {})
              super(http_response)
            end
          end

          # Extensions for HTTP client
          module Client
            #def send_payload(request)
            #  send_request(request) do |api, env|
            #    api.send_traces(env)
            #  end
            #end
          end
        end
      end
    end
  end
end
