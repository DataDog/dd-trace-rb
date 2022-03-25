# typed: ignore

require 'datadog/appsec/instrumentation/gateway'
require 'datadog/appsec/processor'
require 'datadog/appsec/assets'

module Datadog
  module AppSec
    module Contrib
      module Rack
        # Topmost Rack middleware for AppSec
        # This should be inserted just below Datadog::Tracing::Contrib::Rack::TraceMiddleware
        class RequestMiddleware
          def initialize(app, opt = {})
            @app = app

            @processor = Datadog::AppSec::Processor.new
          end

          def call(env)
            return @app.call(env) unless @processor.ready?

            # TODO: handle exceptions, except for @app.call

            context = @processor.context

            env['datadog.waf.context'] = context
            request = ::Rack::Request.new(env)

            request_return, request_response = Instrumentation.gateway.push('rack.request', request) do
              @app.call(env)
            end

            if request_response && request_response.any? { |action, _event| action == :block }
              request_return = [403, { 'Content-Type' => 'text/html' }, [Datadog::AppSec::Assets.blocked]]
            end

            response = ::Rack::Response.new(request_return[2], request_return[0], request_return[1])
            response.instance_eval do
              @waf_context = context
            end

            _, response_response = Instrumentation.gateway.push('rack.response', response)

            request_response.each { |_, e| e.merge!(response: response) } if request_response
            response_response.each { |_, e| e.merge!(request: request) } if response_response
            both_response = (request_response || []) + (response_response || [])

            AppSec::Event.record(*both_response.map { |_action, event| event }) if both_response.any?

            request_return
          end

          def libddwaf_required?
            defined?(Datadog::AppSec::WAF)
          end

          def waf?
            !@waf.nil?
          end

          def require_libddwaf
            require 'libddwaf'
          rescue LoadError => e
            Datadog.logger.warn { "LoadError: libddwaf failed to load: #{e.message}" }
          end
        end
      end
    end
  end
end
