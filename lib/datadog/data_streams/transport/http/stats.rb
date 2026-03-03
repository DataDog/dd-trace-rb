# frozen_string_literal: true

require_relative '../stats'
require_relative '../../../core/transport/http/api/endpoint'
require_relative '../../../core/transport/http/response'

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
                if (content_type = env.request.parcel.content_type)
                  env.headers['content-type'] = content_type
                end
                if (content_encoding = env.request.parcel.content_encoding)
                  env.headers['content-encoding'] = content_encoding
                end

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
