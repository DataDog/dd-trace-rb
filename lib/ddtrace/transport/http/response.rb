require_relative '../response'

module Datadog
  module Transport
    module HTTP
      # Wraps an HTTP response from an adapter.
      #
      # Used by endpoints to wrap responses from adapters with
      # fields or behavior that's specific to that endpoint.
      module Response
        def initialize(http_response)
          @http_response = http_response
        end

        # (see Datadog::Transport::Response#payload)
        def payload
          @http_response.payload
        end

        # (see Datadog::Transport::Response#internal_error?)
        def internal_error?
          @http_response.internal_error?
        end

        # (see Datadog::Transport::Response#unsupported?)
        def unsupported?
          @http_response.unsupported?
        end

        # (see Datadog::Transport::Response#ok?)
        def ok?
          @http_response.ok?
        end

        # (see Datadog::Transport::Response#not_found?)
        def not_found?
          @http_response.not_found?
        end

        # (see Datadog::Transport::Response#client_error?)
        def client_error?
          @http_response.client_error?
        end

        # (see Datadog::Transport::Response#server_error?)
        def server_error?
          @http_response.server_error?
        end

        def code
          @http_response.respond_to?(:code) ? @http_response.code : nil
        end
      end
    end
  end
end
