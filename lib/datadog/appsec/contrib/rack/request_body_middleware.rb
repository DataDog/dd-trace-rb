# frozen_string_literal: true

require_relative 'gateway/request'
require_relative '../../instrumentation/gateway'
require_relative '../../response'

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Rack request body middleware for AppSec
        # This should be inserted just below Rack::JSONBodyParser or
        # legacy Rack::PostBodyContentTypeParser from rack-contrib
        class RequestBodyMiddleware
          def initialize(app, opt = {})
            @app = app
          end

          def call(env)
            context = env[Datadog::AppSec::Ext::CONTEXT_KEY]

            return @app.call(env) unless context

            # TODO: handle exceptions, except for @app.call

            http_response = nil
            block_actions = catch(::Datadog::AppSec::Ext::INTERRUPT) do
              http_response, = Instrumentation.gateway.push('rack.request.body', Gateway::Request.new(env)) do
                @app.call(env)
              end

              nil
            end

            return AppSec::Response.negotiate(env, block_actions).to_rack if block_actions

            http_response
          end
        end
      end
    end
  end
end
