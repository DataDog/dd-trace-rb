# frozen_string_literal: true

require_relative '../core/transport/http'
require_relative '../core/transport/http/env'
require_relative '../core/transport/parcel'
require_relative '../core/transport/request'

module Datadog
  module OpenFeature
    module Transport
      class EncodedParcel
        include Core::Transport::Parcel

        def encode_with(encoder)
          encoder.encode(data)
        end
      end

      class HTTP
        class Spec < Core::Transport::HTTP::API::Spec
          def initialize
            @endpoint = Core::Transport::HTTP::API::Endpoint.new(
              :post, '/evp_proxy/v2/api/v2/exposures'
            )

            super
          end

          def call(env, &block)
            @endpoint.call(env) do |request_env|
              request_env.headers['Content-Type'] = Core::Encoding::JSONEncoder.content_type
              request_env.headers['X-Datadog-EVP-Subdomain'] = 'event-platform-intake'
              request_env.body = env.request.parcel.encode_with(Core::Encoding::JSONEncoder)

              block.call(request_env)
            end
          end
        end

        class Instance < Core::Transport::HTTP::API::Instance
          def send_exposures(env)
            @spec.call(env) { |request_env| call(request_env) }
          end
        end

        def self.build(agent_settings:, logger:)
          Core::Transport::HTTP.build(
            api_instance_class: HTTP::Instance,
            agent_settings: agent_settings,
            logger: logger
          ) { |t| t.api('exposures', HTTP::Spec.new) }.to_transport(self)
        end

        def initialize(apis, default_api, logger:)
          @api = apis[default_api]
          @logger = logger
        end

        def send_exposures(payload)
          request = Core::Transport::Request.new(EncodedParcel.new(payload))
          @api.send_exposures(Core::Transport::HTTP::Env.new(request))
        rescue => e
          message = "Internal error during request. Cause: #{e.class.name} #{e.message} " \
                    "Location: #{Array(e.backtrace).first}"
          @logger.debug(message)

          Core::Transport::InternalErrorResponse.new(e)
        end
      end
    end
  end
end
