# frozen_string_literal: true

require_relative '../stats'
require_relative 'client'
require_relative '../../../core/transport/http/response'
require_relative '../../../core/transport/http/api/endpoint'
require_relative '../../../core/transport/http/api/spec'
require_relative '../../../core/transport/http/api/instance'

module Datadog
  module DataStreams
    module Transport
      module HTTP
        # HTTP transport behavior for Data Streams stats
        module Stats
          # Response from HTTP transport for DSM stats
          class Response
            include Datadog::Core::Transport::HTTP::Response

            def initialize(http_response)
              super
            end
          end

          module API
            # HTTP API Spec for DSM
            class Spec < Core::Transport::HTTP::API::Spec
              attr_accessor :stats

              def send_stats(env, &block)
                raise Core::Transport::HTTP::API::Spec::EndpointNotDefinedError.new('stats', self) if stats.nil?

                stats.call(env, &block)
              end

              def encoder
                # DSM handles encoding in the transport layer (MessagePack + gzip)
                # so we don't need an encoder at the API level
                nil
              end
            end

            # HTTP API Instance for DSM
            class Instance < Core::Transport::HTTP::API::Instance
              def send_stats(env)
                unless spec.is_a?(Stats::API::Spec)
                  raise Core::Transport::HTTP::API::Instance::EndpointNotSupportedError.new(
                    'stats', self
                  )
                end

                spec.send_stats(env) do |request_env|
                  call(request_env)
                end
              end
            end

            # Endpoint for submitting DSM stats data
            class Endpoint < Core::Transport::HTTP::API::Endpoint
              def initialize(path)
                super(:post, path)
              end

              def call(env, &block)
                # Build request
                env.verb = verb
                env.path = path
                env.body = env.request.parcel.data

                # Send request
                http_response = yield(env)

                # Build response
                Response.new(http_response)
              end

              def encoder
                # DSM handles encoding in the transport layer
                nil
              end
            end
          end
        end
      end
    end
  end
end
