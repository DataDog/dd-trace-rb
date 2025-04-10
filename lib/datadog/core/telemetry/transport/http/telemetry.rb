# frozen_string_literal: true

require_relative '../../../transport/http/api/instance'
require_relative '../../../transport/http/api/spec'
require_relative 'client'

module Datadog
  module Core
    module Telemetry
      module Transport
        module HTTP
          module Telemetry
            module Client
              def send_telemetry_payload(request)
                send_request(request) do |api, env|
                  api.send_telemetry(env)
                end
              end
            end

            module API
              class Instance < Core::Transport::HTTP::API::Instance
                def send_telemetry(env)
                  raise Core::Transport::HTTP::API::Instance::EndpointNotSupportedError.new('telemetry', self) unless spec.is_a?(Telemetry::API::Spec)

                  spec.send_telemetry(env) do |request_env|
                    call(request_env)
                  end
                end
              end

              class Spec < Core::Transport::HTTP::API::Spec
                attr_accessor :telemetry

                def send_telemetry(env, &block)
                  raise Core::Transport::HTTP::API::Spec::EndpointNotDefinedError.new('telemetry', self) if telemetry.nil?

                  telemetry.call(env, &block)
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

          HTTP::Client.include(Telemetry::Client)
        end
      end
    end
  end
end
