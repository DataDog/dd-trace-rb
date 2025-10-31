# frozen_string_literal: true

require_relative '../../../core/transport/http/api/endpoint'
require_relative '../../../core/transport/http/api/instance'
require_relative '../../../core/transport/http/api/spec'

module Datadog
  module OpenFeature
    module Transport
      module HTTP
        module Exposures
          module Client
            def send_exposures(request)
              send_request(request) do |api, env|
                api.send_exposures(env)
              end
            end
          end

          module API
            class Instance < Core::Transport::HTTP::API::Instance
              def send_exposures(env)
                unless spec.is_a?(Exposures::API::Spec)
                  raise Core::Transport::HTTP::API::Instance::EndpointNotSupportedError.new('exposures', self)
                end

                spec.send_exposures(env) do |request_env|
                  call(request_env)
                end
              end
            end

            class Spec < Core::Transport::HTTP::API::Spec
              attr_accessor :exposures

              def send_exposures(env, &block)
                raise Core::Transport::HTTP::API::Spec::EndpointNotDefinedError.new('exposures', self) if exposures.nil?

                exposures.call(env, &block)
              end
            end

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
                request_headers = env.request.respond_to?(:headers) ? env.request.headers : nil
                env.headers.update(request_headers) if request_headers && !request_headers.empty?

                env.body = if env.request.parcel.respond_to?(:encode_with)
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
