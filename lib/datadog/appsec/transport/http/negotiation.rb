# typed: false

require 'json'

require_relative '../negotiation'
require_relative 'client'
require_relative '../../../../ddtrace/transport/http/response'
require_relative '../../../../ddtrace/transport/http/api/endpoint'
# TODO: because of include in http/negotiation
#require_relative '../../../../ddtrace/transport/http/api/instance'
require_relative 'api/instance'

module Datadog
  module AppSec
    module Transport
      module HTTP
        # HTTP transport behavior for agent feature negotiation
        module Negotiation
          # Response from HTTP transport for agent feature negotiation
          class Response
            include Datadog::Transport::HTTP::Response
            include AppSec::Transport::Negotiation::Response

            def initialize(http_response, options = {})
              super(http_response)
            end
          end

          # Extensions for HTTP client
          module Client
            def send_payload(request)
              send_request(request) do |api, env|
                api.send_info(env)
              end
            end
          end

          module API
            # Extensions for HTTP API Spec
            module Spec
              attr_reader :info

              def info=(endpoint)
                @info = endpoint
              end

              def send_info(env, &block)
                raise NoNegotiationEndpointDefinedError, self if info.nil?

                info.call(env, &block)
              end

              # Raised when traces sent but no traces endpoint is defined
              class NoNegotiationEndpointDefinedError < StandardError
                attr_reader :spec

                def initialize(spec)
                  @spec = spec
                end

                def message
                  'No info endpoint is defined for API specification!'
                end
              end
            end

            # Extensions for HTTP API Instance
            module Instance
              def send_info(env)
                raise NegotiationNotSupportedError, spec unless spec.is_a?(Negotiation::API::Spec)

                spec.send_info(env) do |request_env|
                  call(request_env)
                end
              end

              # Raised when traces sent to API that does not support traces
              class NegotiationNotSupportedError < StandardError
                attr_reader :spec

                def initialize(spec)
                  @spec = spec
                end

                def message
                  'Info not supported for this API!'
                end
              end
            end

            # Endpoint for negotiation
            class Endpoint < Datadog::Transport::HTTP::API::Endpoint
              HEADER_CONTENT_TYPE = 'Content-Type'.freeze

              def initialize(path)
                super(:get, path)
              end

              def call(env, &block)
                # Query for response
                http_response = super(env, &block)

                # Process the response
                body = JSON.parse(http_response.payload)

                response_options = {}

                # Build and return a trace response
                Negotiation::Response.new(http_response, response_options)
              end
            end
          end

          # Add negotiation behavior to transport components
          HTTP::Client.include(Negotiation::Client)
          HTTP::API::Spec.include(Negotiation::API::Spec)
          HTTP::API::Instance.include(Negotiation::API::Instance)
        end
      end
    end
  end
end
