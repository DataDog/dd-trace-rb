require 'json'

require 'ddtrace/transport/traces'
require 'ddtrace/transport/http/response'
require 'ddtrace/transport/http/api/endpoint'

module Datadog
  module Transport
    module HTTP
      # HTTP transport behavior for traces
      module Traces
        # Response from HTTP transport for traces
        class Response
          include HTTP::Response
          include Transport::Traces::Response

          def initialize(http_response, options = {})
            super(http_response)
            @service_rates = options.fetch(:service_rates, nil)
          end
        end

        # Extensions for HTTP client
        module Client
          def send_traces(traces)
            request = Transport::Traces::Request.new(traces)

            send_request(request) do |api, env|
              api.send_traces(env)
            end
          end
        end

        module API
          # Extensions for HTTP API Spec
          module Spec
            attr_reader :traces

            def traces=(endpoint)
              @traces = endpoint
            end

            def send_traces(env, &block)
              traces.call(env, &block)
            end
          end

          # Extensions for HTTP API Instance
          module Instance
            def send_traces(env)
              spec.send_traces(env) do |request_env|
                call(request_env)
              end
            end
          end

          # Endpoint for submitting trace data
          class Endpoint < HTTP::API::Endpoint
            HEADER_CONTENT_TYPE = 'Content-Type'.freeze
            HEADER_TRACE_COUNT = 'X-Datadog-Trace-Count'.freeze
            SERVICE_RATE_KEY = 'rate_by_service'.freeze

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
              env.headers[HEADER_TRACE_COUNT] = env.request.parcel.count.to_s

              # Encode body & type
              env.headers[HEADER_CONTENT_TYPE] = encoder.content_type
              env.body = env.request.parcel.encode_with(encoder)

              # Query for response
              http_response = super(env, &block)

              # Process the response
              response_options = {}.tap do |options|
                # Parse service rates, if configured to do so.
                if service_rates? && !http_response.payload.to_s.empty?
                  body = JSON.parse(http_response.payload)
                  if body.is_a?(Hash) && body.key?(SERVICE_RATE_KEY)
                    options[:service_rates] = body[SERVICE_RATE_KEY]
                  end
                end
              end

              # Build and return a trace response
              Traces::Response.new(http_response, response_options)
            end
          end
        end

        # Add traces behavior to transport components
        HTTP::Client.send(:include, Traces::Client)
        HTTP::API::Spec.send(:include, Traces::API::Spec)
        HTTP::API::Instance.send(:include, Traces::API::Instance)
      end
    end
  end
end
