require 'json'

module Datadog
  module Transport
    module HTTP
      module API
        # Endpoint for traces
        class TraceEndpoint
          HEADER_CONTENT_TYPE = 'Content-Type'.freeze
          HEADER_TRACE_COUNT = 'X-Datadog-Trace-Count'.freeze

          attr_reader \
            :encoder

          def initialize(encoder)
            @encoder = encoder
          end

          def call(env)
            # Add trace count header
            env.headers[HEADER_TRACE_COUNT] = env.request.parcel.count.to_s

            # Encode body & type
            env.verb = :post
            env.headers[HEADER_CONTENT_TYPE] = encoder.content_type
            env.body = env.request.parcel.encode_with(encoder)

            yield(env).tap do |response|
              # Parse service rates from response
              if body_service_rates?
                body = JSON.parse(response.payload)
                if body.is_a?(Hash) && body.key?('rate_by_service')
                  # TODO: Parse into traces response
                end
              end
            end
          end
        end
      end
    end
  end
end
