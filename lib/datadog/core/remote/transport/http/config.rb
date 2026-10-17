# frozen_string_literal: true

require "json"

require_relative "../../../transport/http/api/endpoint"
require_relative "../../../transport/http/response"
require_relative "../../../utils/base64_codec"
require_relative "../../../utils/truncation"
require_relative "../../configuration"

module Datadog
  module Core
    module Remote
      module Transport
        module HTTP
          # HTTP transport behavior for remote configuration
          module Config
            # Response from HTTP transport for remote configuration
            class Response
              include Core::Transport::HTTP::Response

              def initialize(http_response, options = {}) # standard:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
                super(http_response)

                raise AgentErrorResponse.new(http_response.code, http_response.payload) if http_response.code != 200

                begin
                  payload = JSON.parse(http_response.payload, symbolize_names: true)
                rescue JSON::ParserError => e
                  raise ParseError.new(:roots, e)
                end

                raise TypeError.new("payload", payload, Hash) unless payload.is_a?(Hash)

                @empty = true if payload.empty?

                # TODO: these fallbacks should be improved
                roots = payload[:roots] || []
                targets = payload[:targets] || Datadog::Core::Utils::Base64Codec.strict_encode64("{}")
                target_files = payload[:target_files] || []
                client_configs = payload[:client_configs] || []

                raise TypeError.new("roots", roots, Array) unless roots.is_a?(Array)

                @roots = roots.map do |root|
                  raise TypeError.new("roots entry", root, String) unless root.is_a?(String)

                  decoded = begin
                    Datadog::Core::Utils::Base64Codec.strict_decode64(root) # TODO: unprocessed, don't symbolize_names
                  rescue ArgumentError
                    raise DecodeError.new(:roots, root)
                  end

                  parsed = begin
                    JSON.parse(decoded)
                  rescue JSON::ParserError
                    raise ParseError.new(:roots, decoded)
                  end

                  # TODO: perform more processing to validate content. til then, no freeze

                  parsed
                end

                raise TypeError.new("targets", targets, String) unless targets.is_a?(String)

                @targets = begin
                  decoded = begin
                    Datadog::Core::Utils::Base64Codec.strict_decode64(targets)
                  rescue ArgumentError
                    raise DecodeError.new(:targets, targets)
                  end

                  parsed = begin
                    JSON.parse(decoded) # TODO: unprocessed, don't symbolize_names
                  rescue JSON::ParserError
                    raise ParseError.new(:targets, decoded)
                  end

                  # TODO: perform more processing to validate content. til then, no freeze

                  parsed
                end

                raise TypeError.new("target_files", target_files, Array) unless target_files.is_a?(Array)

                @target_files = target_files.map do |h|
                  raise TypeError.new("target_files entry", h, Hash) unless h.is_a?(Hash)
                  raise KeyError.new(:raw) unless h.key?(:raw) # rubocop:disable Style/RaiseArgs
                  raise KeyError.new(:path) unless h.key?(:path) # rubocop:disable Style/RaiseArgs

                  raw = h[:raw]

                  raise TypeError.new("raw", raw, String) unless raw.is_a?(String)

                  content = begin
                    Datadog::Core::Utils::Base64Codec.strict_decode64(raw)
                  rescue ArgumentError
                    raise DecodeError.new(:target_files, raw)
                  end

                  {
                    path: h[:path].freeze,
                    content: content.freeze,
                  }
                end.freeze

                @client_configs = client_configs.map do |s|
                  raise TypeError.new("client_configs entry", s, String) unless s.is_a?(String)

                  s.freeze
                end.freeze
              end

              attr_reader :roots, :targets, :target_files, :client_configs

              def empty?
                @empty
              end

              def inspect
                "#{super}, #{
                  {
                    roots: @roots,
                    targets: @targets,
                    target_files: @target_files,
                    client_configs: @client_configs,
                  }}"
              end

              # When an expected key is missing
              class KeyError < StandardError
                def initialize(key)
                  message = "key not found: #{key.inspect}"

                  super(message)
                end
              end

              # Base class for Remote Configuration Config errors
              class ConfigError < StandardError
              end

              # When the agent returned an error response to our request
              class AgentErrorResponse < ConfigError
                def initialize(code, body)
                  truncated_body = Core::Utils::Truncation.truncate_in_middle(body, 700, 300)
                  message = "Agent returned an error response: #{code}: #{truncated_body}"
                  super(message)
                end
              end

              # When an expected value type is incorrect
              class TypeError < ConfigError
                def initialize(field, value, expected_type)
                  super(Configuration.invalid_type_message(field, value, expected_type))
                end
              end

              # When value decoding fails
              class DecodeError < ConfigError
                def initialize(key, value)
                  message = "could not decode key #{key.inspect}: #{value.inspect}"

                  super(message)
                end
              end

              # When value parsing fails
              class ParseError < ConfigError
                def initialize(key, value)
                  message = "could not parse key #{key.inspect}: #{value.inspect}"

                  super(message)
                end
              end
            end

            module API
              # Endpoint for remote configuration
              class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
                HEADER_CONTENT_TYPE = "Content-Type"

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
                  http_response = super

                  response_options = {}

                  # Build and return a response
                  Config::Response.new(http_response, response_options)
                end
              end
            end
          end
        end
      end
    end
  end
end
