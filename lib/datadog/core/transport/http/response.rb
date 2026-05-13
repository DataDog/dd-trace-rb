# frozen_string_literal: true

require_relative '../../../core/transport/response'

module Datadog
  module Core
    module Transport
      module HTTP
        # Wraps an HTTP response from an adapter.
        #
        # Used by endpoints to wrap responses from adapters with
        # fields or behavior that's specific to that endpoint.
        module Response
          # Inherit the abstract transport response interface so includers pick up the
          # shared default methods (e.g. json_content_type?) without re-declaring them here.
          include Datadog::Core::Transport::Response

          def initialize(http_response)
            @http_response = http_response
          end

          # (see Datadog::Core::Transport::Response#payload)
          def payload
            @http_response.payload
          end

          # (see Datadog::Core::Transport::Response#internal_error?)
          def internal_error?
            @http_response.internal_error?
          end

          # (see Datadog::Core::Transport::Response#unsupported?)
          def unsupported?
            @http_response.unsupported?
          end

          # (see Datadog::Core::Transport::Response#ok?)
          def ok?
            @http_response.ok?
          end

          # (see Datadog::Core::Transport::Response#not_found?)
          def not_found?
            @http_response.not_found?
          end

          # (see Datadog::Core::Transport::Response#client_error?)
          def client_error?
            @http_response.client_error?
          end

          # (see Datadog::Core::Transport::Response#server_error?)
          def server_error?
            @http_response.server_error?
          end

          def code
            @http_response.respond_to?(:code) ? @http_response.code : nil
          end

          def headers
            @http_response.respond_to?(:headers) ? @http_response.headers : {}
          end

          # (see Datadog::Core::Transport::Response#content_type)
          def content_type
            @http_response.respond_to?(:content_type) ? @http_response.content_type : nil
          end
        end

        # Raised when a response that was expected to contain JSON did not declare a
        # JSON Content-Type. Carries the offending response so callers (and the
        # transport client's exception logger) can include status, content type, and
        # payload in their diagnostics.
        class NotJsonResponseError < StandardError
          attr_reader :http_response

          def initialize(http_response)
            @http_response = http_response
            payload = http_response.payload.to_s
            truncated_payload = (payload.length > 1000) ? "#{payload[0, 1000]}... (truncated)" : payload
            super(
              "Response is not declared as JSON " \
              "(Content-Type: #{http_response.content_type.inspect}, " \
              "status: #{http_response.code.inspect}, " \
              "payload: #{truncated_payload.inspect})"
            )
          end
        end
      end
    end
  end
end
