# frozen_string_literal: true

require_relative '../../../../core/transport/http/api/endpoint'
require_relative '../../../../core/transport/http/response'

module Datadog
  module Tracing
    module Stats
      module Transport
        module HTTP
          # HTTP transport behavior for client-side trace stats
          module StatsEndpoint
            # Response from HTTP transport for trace stats
            class Response
              include Datadog::Core::Transport::HTTP::Response

              def initialize(http_response)
                super
              end
            end

            module API
              # Endpoint for submitting client-side stats to /v0.6/stats
              class Endpoint < Core::Transport::HTTP::API::Endpoint
                def initialize(path)
                  super(:post, path)
                end

                def call(env, &block)
                  # Build request
                  env.verb = verb
                  env.path = path
                  env.body = env.request.parcel.data
                  if (content_type = env.request.parcel.content_type)
                    env.headers['content-type'] = content_type
                  end

                  # Send request
                  http_response = yield(env)

                  # Build response
                  Response.new(http_response)
                end

                def encoder
                  nil
                end
              end
            end
          end
        end
      end
    end
  end
end
