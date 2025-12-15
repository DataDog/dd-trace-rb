# frozen_string_literal: true

require 'json'

require_relative '../../../core/transport/http/response'
require_relative '../../../core/transport/http/api/endpoint'
require_relative '../../../core/transport/http/api/instance'
require_relative '../traces'

module Datadog
  module Tracing
    module Transport
      module HTTP
        # HTTP transport behavior for traces
        module Traces
          # Response from HTTP transport for traces
          class Response
            include Datadog::Core::Transport::HTTP::Response
            include Datadog::Tracing::Transport::Traces::Response

            def initialize(http_response, options = {})
              super(http_response)
              @service_rates = options.fetch(:service_rates, nil)
              @trace_count = options.fetch(:trace_count, 0)
            end
          end

          module API
            # Endpoint for submitting trace data
            class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
              HEADER_CONTENT_TYPE = 'Content-Type'
              HEADER_TRACE_COUNT = 'X-Datadog-Trace-Count'
              SERVICE_RATE_KEY = 'rate_by_service'

              attr_reader \
                :encoder

              def initialize(path, encoder, options = {})
                super(:post, path)
                @encoder = encoder
                @service_rates = options.fetch(:service_rates, false)
              end

              def service_rates?
                @service_rates == true
              end

              def call(env, &block)
                # Add trace count header
                env.headers[HEADER_TRACE_COUNT] = env.request.parcel.trace_count.to_s

                # Encode body & type
                env.headers[HEADER_CONTENT_TYPE] = encoder.content_type
                env.body = env.request.parcel.data

                # Query for response
                http_response = super

                # Process the response
                response_options = {trace_count: env.request.parcel.trace_count}.tap do |options|
                  # Parse service rates, if configured to do so.
                  if service_rates? && !http_response.payload.to_s.empty?
                    body = JSON.parse(http_response.payload)
                    options[:service_rates] = body[SERVICE_RATE_KEY] if body.is_a?(Hash) && body.key?(SERVICE_RATE_KEY)
                  end
                end

                # Build and return a trace response
                Traces::Response.new(http_response, response_options)
              end
            end
          end
        end
      end
    end
  end
end
