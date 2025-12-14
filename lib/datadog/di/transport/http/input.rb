# frozen_string_literal: true

require_relative '../../../core/transport/http/api/endpoint'

module Datadog
  module DI
    module Transport
      module HTTP
        module Input
          module API
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
                env.query = {
                  # DEV: In theory we could serialize the tags here
                  # rather than requiring them to be pre-serialized.
                  # In practice the tags should be relatively static
                  # (they would change when process forks, and hostname
                  # could change at any time but probably we should ignore
                  # those changes), therefore serializing the tags
                  # every time would be wasteful.
                  ddtags: env.request.serialized_tags,
                }

                super
              end
            end
          end
        end
      end
    end
  end
end
