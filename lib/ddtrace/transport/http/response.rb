require 'forwardable'
require 'ddtrace/transport/response'

module Datadog
  module Transport
    module HTTP
      # Wraps an HTTP response from an adapter.
      #
      # Used by endpoints to wrap responses from adapters with
      # fields or behavior that's specific to that endpoint.
      module Response
        extend ::Forwardable

        def initialize(http_response)
          @http_response = http_response
        end

        def_delegators :@http_response, *Transport::Response.instance_methods

        def code
          @http_response.respond_to?(:code) ? @http_response.code : nil
        end
      end
    end
  end
end
