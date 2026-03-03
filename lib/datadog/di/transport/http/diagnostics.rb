# frozen_string_literal: true

require_relative '../../../core/transport/http/api/endpoint'

module Datadog
  module DI
    module Transport
      module HTTP
        module Diagnostics
          module API
            class Endpoint < Datadog::Core::Transport::HTTP::API::Endpoint
              attr_reader :encoder

              def initialize(path, encoder)
                super(:post, path)
                @encoder = encoder
              end

              def call(env, &block)
                event_payload = Core::Vendor::Multipart::Post::UploadIO.new(
                  StringIO.new(env.request.parcel.data),
                  env.request.parcel.content_type,
                  'event.json',
                )
                env.form = {'event' => event_payload}

                super
              end
            end
          end
        end
      end
    end
  end
end
