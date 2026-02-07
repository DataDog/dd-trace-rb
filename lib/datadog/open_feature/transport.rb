# frozen_string_literal: true

require_relative '../core/encoding'
require_relative '../core/transport/http'
require_relative '../core/transport/http/env'
require_relative '../core/transport/http/api/endpoint'
require_relative '../core/transport/http/api/instance'
require_relative '../core/transport/parcel'
require_relative '../core/transport/request'

module Datadog
  module OpenFeature
    module Transport
      class HTTP
        class Spec
          def initialize
            @endpoint = Core::Transport::HTTP::API::Endpoint.new(
              :post, '/evp_proxy/v2/api/v2/exposures'
            )
          end

          # TODO rename to send_request?
          def call(env, &block)
            @endpoint.call(env) do |request_env|
              request_env.headers['Content-Type'] = env.request.parcel.content_type || Core::Encoding::JSONEncoder.content_type
              request_env.headers['X-Datadog-EVP-Subdomain'] = 'event-platform-intake'
              request_env.body = env.request.parcel.data

              block.call(request_env)
            end
          end
        end

        def self.build(agent_settings:, logger:)
          Core::Transport::HTTP.build(
            agent_settings: agent_settings,
            logger: logger
          ) { |t| t.api('exposures', HTTP::Spec.new) }.to_transport(self)
        end

        def initialize(apis, default_api, logger:)
          @api = apis[default_api]
          @logger = logger
        end

        def send_exposures(payload)
          encoder = Core::Encoding::JSONEncoder
          parcel = Core::Transport::Parcel.new(
            encoder.encode(payload),
            content_type: encoder.content_type
          )
          request = Core::Transport::Request.new(parcel)

          @api.endpoint.call(Core::Transport::HTTP::Env.new(request)) do |env|
            @api.call(env)
          end
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
