# typed: ignore

require_relative '../../instrumentation/gateway'
require_relative '../../assets'

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
            context = env['datadog.waf.context']

            return @app.call(env) unless context

            # TODO: handle exceptions, except for @app.call

            request = ::Rack::Request.new(env)

            request_return, request_response = Instrumentation.gateway.push('rack.request.body', request) do
              @app.call(env)
            end

            if request_response && request_response.any? { |action, _event| action == :block }
              request_return = [403, { 'Content-Type' => 'text/html' }, [Datadog::AppSec::Assets.blocked]]
            end

            request_return
          end
        end
      end
    end
  end
end
