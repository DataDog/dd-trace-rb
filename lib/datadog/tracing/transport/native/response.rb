# frozen_string_literal: true

require 'json'

module Datadog
  module Tracing
    module Transport
      module Native
        # Response from the native trace exporter.
        #
        # Constructed by the C extension after a send completes (or fails).
        # Implements the same predicate interface as the HTTP transport's
        # response so callers can treat both uniformly.
        class Response
          attr_reader :trace_count, :payload

          def initialize(ok:, internal_error: false, server_error: false, client_error: false,
                         not_found: false, unsupported: false, trace_count: 0, payload: nil)
            @ok = ok
            @internal_error = internal_error
            @server_error = server_error
            @client_error = client_error
            @not_found = not_found
            @unsupported = unsupported
            @trace_count = trace_count
            @payload = payload
          end

          def ok?
            @ok
          end

          def internal_error?
            @internal_error
          end

          def server_error?
            @server_error
          end

          def client_error?
            @client_error
          end

          def not_found?
            @not_found
          end

          def unsupported?
            @unsupported
          end

          SERVICE_RATE_KEY = 'rate_by_service'

          # Parse the agent's JSON response body and extract the
          # +rate_by_service+ map.  Returns +nil+ when the payload
          # is absent or does not contain sampling rates.
          def service_rates
            body = payload
            return nil if body.nil? || body.empty?

            parsed = JSON.parse(body)
            parsed[SERVICE_RATE_KEY] if parsed.is_a?(Hash)
          rescue JSON::ParserError
            nil
          end
        end
      end
    end
  end
end
