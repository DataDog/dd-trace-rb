# frozen_string_literal: true

require_relative '../../../core/transport/http/api/instance'
require_relative '../../../core/transport/http/api/spec'
require_relative 'client'

module Datadog
  module DI
    module Transport
      module HTTP
        module Input
          module Client
            def send_input_payload(request)
              send_request(request) do |api, env|
                api.send_input(env)
              end
            end
          end

          module API
            class Instance < Core::Transport::HTTP::API::Instance
              def send_input(env)
                raise Core::Transport::HTTP::API::Instance::EndpointNotSupportedError.new('input', self) unless spec.is_a?(Input::API::Spec)

                spec.send_input(env) do |request_env|
                  call(request_env)
                end
              end
            end

            class Spec < Core::Transport::HTTP::API::Spec
              attr_accessor :input

              def send_input(env, &block)
                raise Core::Transport::HTTP::API::Spec::EndpointNotDefinedError.new('input', self) if input.nil?

                input.call(env, &block)
              end
            end

            class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
              HEADER_CONTENT_TYPE = 'Content-Type'

              attr_reader \
                :encoder

              def initialize(path, encoder)
                super(:post, path)
                @encoder = encoder
              end

              def call(env, &block)
                # Encode body & type
                env.headers[HEADER_CONTENT_TYPE] = encoder.content_type
                env.body = env.request.parcel.data

                super
              end
            end
          end
        end

        HTTP::Client.include(Input::Client)
      end
    end
  end
end
