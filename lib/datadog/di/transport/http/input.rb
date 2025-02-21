# frozen_string_literal: true

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
            module Instance
              def send_input(env)
                raise TracesNotSupportedError, spec unless spec.is_a?(Input::API::Spec)

                spec.send_input(env) do |request_env|
                  call(request_env)
                end
              end
            end

            module Spec
              attr_accessor :input

              def send_input(env, &block)
                raise NoTraceEndpointDefinedError, self if input.nil?

                input.call(env, &block)
              end

              # Raised when traces sent but no traces endpoint is defined
              class NoTraceEndpointDefinedError < StandardError
                attr_reader :spec

                def initialize(spec)
                  super

                  @spec = spec
                end

                def message
                  'No trace endpoint is defined for API specification!'
                end
              end
            end

            # Endpoint for negotiation
            class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
              HEADER_CONTENT_TYPE = 'Content-Type'

              attr_reader \
                :encoder

              def initialize(path, encoder)
                super(:post, path)
                @encoder = encoder
              end

              def call(env, &block)
                # Add trace count header
                # env.headers[HEADER_TRACE_COUNT] = env.request.parcel.trace_count.to_s

                # Encode body & type
                env.headers[HEADER_CONTENT_TYPE] = encoder.content_type
                env.body = env.request.parcel.data

                super(env, &block)
              end
            end
          end
        end

        HTTP::Client.include(Input::Client)
      end
    end
  end
end
