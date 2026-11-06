# frozen_string_literal: true

require_relative "gateway/request"
require_relative "../../instrumentation/gateway"
require_relative "../../response"

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Rack request body middleware for AppSec
        # This should be inserted just below Rack::JSONBodyParser or
        # legacy Rack::PostBodyContentTypeParser from rack-contrib
        class RequestBodyMiddleware
          # TODO: opt is never used, it can probably be safely removed
          def initialize(app, opt = {}) # steep:ignore DifferentMethodParameterKind
            @app = app
          end

          def call(env)
            context = env[Datadog::AppSec::Ext::CONTEXT_KEY]

            return @app.call(env) unless context

            # TODO: handle exceptions, except for @app.call

            http_response = nil #: Rack::response?
            completed = false
            context.catch do
              http_response, _request = Instrumentation.gateway.push("rack.request.body", Gateway::Request.new(env)) do
                @app.call(env)
              end
              completed = true
            end

            if !completed && (http_response.nil? || !context.shared?)
              return AppSec::Response.from_interrupt_params(context.state[:interrupt_params], env["HTTP_ACCEPT"]).to_rack
            end

            # Steep can't see that the catch block always populates http_response
            # when no interrupt is thrown.
            http_response #: Rack::response
          end
        end
      end
    end
  end
end
