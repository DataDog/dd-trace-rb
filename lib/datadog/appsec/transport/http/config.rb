# typed: false

require 'json'
require 'base64'

require_relative '../config'
require_relative 'client'
require_relative '../../../../ddtrace/transport/http/response'
require_relative '../../../../ddtrace/transport/http/api/endpoint'
# TODO: because of include in http/config
#require_relative '../../../../ddtrace/transport/http/api/instance'
require_relative 'api/instance'

module Datadog
  module AppSec
    module Transport
      module HTTP
        # HTTP transport behavior for remote configuration
        module Config
          # Response from HTTP transport for remote configuration
          class Response
            include Datadog::Transport::HTTP::Response
            include AppSec::Transport::Config::Response

            def initialize(http_response, options = {})
              super(http_response)

              # TODO: keys should be symbols
              @roots = options['roots'].map { |e| JSON.parse(Base64.decode64(e)) }
              @targets = JSON.parse(Base64.decode64(options['targets']))
              @target_files = options['target_files'].map { |h| { path: h['path'], content: StringIO.new(Base64.decode64(h['raw'])) } }
              @client_configs = options['client_configs'].dup # [::String]
            end
          end

          # Extensions for HTTP client
          module Client
            def send_config_payload(request)
              send_request(request) do |api, env|
                api.send_config(env)
              end
            end
          end

          module API
            # Extensions for HTTP API Spec
            module Spec
              attr_reader :config

              def config=(endpoint)
                @config = endpoint
              end

              def send_config(env, &block)
                raise NoConfigEndpointDefinedError, self if config.nil?

                config.call(env, &block)
              end

              # Raised when traces sent but no traces endpoint is defined
              class NoConfigEndpointDefinedError < StandardError
                attr_reader :spec

                def initialize(spec)
                  @spec = spec
                end

                def message
                  'No config endpoint is defined for API specification!'
                end
              end
            end

            # Extensions for HTTP API Instance
            module Instance
              def send_config(env)
                raise ConfigNotSupportedError, spec unless spec.is_a?(Config::API::Spec)

                spec.send_config(env) do |request_env|
                  call(request_env)
                end
              end

              # Raised when traces sent to API that does not support traces
              class ConfigNotSupportedError < StandardError
                attr_reader :spec

                def initialize(spec)
                  @spec = spec
                end

                def message
                  'Config not supported for this API!'
                end
              end
            end

            # Endpoint for remote configuration
            class Endpoint < Datadog::Transport::HTTP::API::Endpoint
              HEADER_CONTENT_TYPE = 'Content-Type'.freeze

              attr_reader :encoder

              def initialize(path, encoder)
                super(:post, path)
                @encoder = encoder
              end

              def call(env, &block)
                # Encode body & type
                env.headers[HEADER_CONTENT_TYPE] = encoder.content_type
                env.body = env.request.parcel.data

                # Query for response
                http_response = super(env, &block)

                # Process the response
                body = JSON.parse(http_response.payload)

                # TODO: there should be more processing here to ensure a proper response_options
                response_options = body.is_a?(Hash) ? body : {}

                # Build and return a trace response
                Config::Response.new(http_response, response_options)
              end
            end
          end

          # Add remote configuration behavior to transport components
          ###### overrides send_payload! which calls send_<endpoint>! kills any other possible endpoint!
          HTTP::Client.include(Config::Client)
          HTTP::API::Spec.include(Config::API::Spec)
          HTTP::API::Instance.include(Config::API::Instance)
        end
      end
    end
  end
end
