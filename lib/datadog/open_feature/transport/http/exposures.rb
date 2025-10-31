# frozen_string_literal: true

require_relative '../../../core/transport/http/api/endpoint'
require_relative '../../../core/transport/http/api/instance'
require_relative '../../../core/transport/http/api/spec'

require_relative 'client'

module Datadog
  module OpenFeature
    module Transport
      module HTTP
        # HTTP transport behavior for exposure events
        module Exposures
          # Extensions for HTTP client
          module Client
            def send_exposures_payload(request)
              send_request(request) do |api, env|
                api.send_exposures(env)
              end
            end
          end

          module API
            # HTTP API Spec
            class Spec < Core::Transport::HTTP::API::Spec
              attr_accessor :exposures

              def send_exposures(env, &block)
                if exposures.nil?
                  raise Core::Transport::HTTP::API::Spec::EndpointNotDefinedError.new(
                    'exposures', self
                  )
                end

                exposures.call(env, &block)
              end
            end

            # HTTP API Instance
            class Instance < Core::Transport::HTTP::API::Instance
              def send_exposures(env)
                unless spec.is_a?(Exposures::API::Spec)
                  raise Core::Transport::HTTP::API::Instance::EndpointNotSupportedError.new(
                    'exposures', self
                  )
                end

                spec.send_exposures(env) do |request_env|
                  call(request_env)
                end
              end
            end

            # Endpoint for submitting exposure events data
            class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
              HEADER_CONTENT_TYPE = 'Content-Type'
              HEADER_SUBDOMAIN = 'X-Datadog-EVP-Subdomain'
              SUBDOMAIN_VALUE = 'event-platform-intake'

              attr_reader :encoder

              def initialize(path, encoder)
                super(:post, path)
                @encoder = encoder
              end

              def call(env, &block)
                env.headers[HEADER_CONTENT_TYPE] = encoder.content_type
                env.headers[HEADER_SUBDOMAIN] = SUBDOMAIN_VALUE
                env.body =
                  if env.request.parcel.respond_to?(:encode_with)
                    env.request.parcel.encode_with(encoder)
                  else
                    encoder.encode(env.request.parcel.data)
                  end

                super
              end
            end
          end
        end

        HTTP::Client.include(Exposures::Client)
      end
    end
  end
end
