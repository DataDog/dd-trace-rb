# frozen_string_literal: true

require 'json'
require 'base64'

require_relative '../config'
require_relative 'client'
require_relative '../../../../ddtrace/transport/http/response'
require_relative '../../../../ddtrace/transport/http/api/endpoint'

# TODO: Decouple standard transport/http/api/instance
#
# Separate classes are needed because transport/http/trace includes
# Trace::API::Instance which closes over and uses a single spec, which is
# negotiated as either /v3 or /v4 for the whole API at the spec level, but we
# need an independent toplevel path at the endpoint level.
#
# Separate classes are needed because of `include Trace::API::Instance`.
#
# Below should be:
# require_relative '../../../../ddtrace/transport/http/api/instance'
require_relative 'api/instance'
# Below should be:
# require_relative '../../../../ddtrace/transport/http/api/spec'
require_relative 'api/spec'

module Datadog
  module Core
    module Transport
      module HTTP
        # HTTP transport behavior for remote configuration
        module Config
          # Response from HTTP transport for remote configuration
          class Response
            include Datadog::Transport::HTTP::Response
            include Core::Transport::Config::Response

            def initialize(http_response, options = {}) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
              super(http_response)

              # TODO: these fallbacks should be improved
              roots = options[:roots] || []
              targets = options[:targets] || ''
              target_files = options[:target_files] || []
              client_configs = options[:client_configs] || []

              raise TypeError.new(Array, roots) unless roots.is_a?(Array)

              @roots = roots.map do |e|
                raise TypeError.new(String, e) unless e.is_a?(String)

                begin
                  decoded = Base64.strict_decode64(e) # TODO: unprocessed, don't symbolize_names
                rescue ArgumentError
                  raise DecodeError.new(:roots, e)
                end

                begin
                  parsed = JSON.parse(decoded)
                rescue JSON::ParserError
                  raise ParseError.new(:roots, e)
                end

                # TODO: perform more processing to validate content. til then, no freeze

                parsed
              end

              raise TypeError.new(String, targets) unless targets.is_a?(String)

              @targets = begin
                begin
                  decoded = Base64.strict_decode64(targets)
                rescue ArgumentError
                  raise DecodeError.new(:targets, e)
                end

                begin
                  parsed = JSON.parse(decoded) # TODO: unprocessed, don't symbolize_names
                rescue JSON::ParserError
                  raise ParseError.new(:targets, e)
                end

                # TODO: perform more processing to validate content. til then, no freeze

                parsed
              end

              raise TypeError.new(Array, target_files) unless target_files.is_a?(Array)

              @target_files = target_files.map do |h|
                raise TypeError.new(Hash, h) unless h.is_a?(Hash)
                raise KeyError.new(:raw) unless h.key?(:raw) # rubocop:disable Style/RaiseArgs
                raise KeyError.new(:path) unless h.key?(:path) # rubocop:disable Style/RaiseArgs

                raw = h[:raw]

                raise TypeError.new(String, raw) unless raw.is_a?(String)

                begin
                  content = Base64.strict_decode64(raw)
                rescue ArgumentError
                  raise DecodeError.new(:target_files, raw)
                end

                {
                  path: h[:path].freeze,
                  content: StringIO.new(content.freeze),
                }
              end.freeze

              @client_configs = client_configs.map do |s|
                raise TypeError.new(String, s) unless s.is_a?(String)

                s.freeze
              end.freeze
            end

            # When an expected key is missing
            class KeyError < StandardError
              def initialize(key)
                message = "key not found: #{key.inspect}"

                super(message)
              end
            end

            # When an expected value type is incorrect
            class TypeError < StandardError
              def initialize(type, value)
                message = "not a #{type}: #{value.inspect}"

                super(message)
              end
            end

            # When value decoding fails
            class DecodeError < StandardError
              def initialize(key, value)
                message = "could not decode key #{key.inspect}: #{value.inspect}"

                super(message)
              end
            end

            # When value parsing fails
            class ParseError < StandardError
              def initialize(key, value)
                message = "could not parse key #{key.inspect}: #{value.inspect}"

                super(message)
              end
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
                  super()

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
                  super()

                  @spec = spec
                end

                def message
                  'Config not supported for this API!'
                end
              end
            end

            # Endpoint for remote configuration
            class Endpoint < Datadog::Transport::HTTP::API::Endpoint
              HEADER_CONTENT_TYPE = 'Content-Type'

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
                body = JSON.parse(http_response.payload, symbolize_names: true)

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
