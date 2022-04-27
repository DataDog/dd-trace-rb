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

            @first_request = true
            @processor = Datadog::AppSec::Processor.new
          end

          def call(env)
            return @app.call(env) unless @processor.ready?

            # TODO: handle exceptions, except for @app.call

            context = @processor.new_context

            env['datadog.waf.context'] = context
            request = ::Rack::Request.new(env)

            add_appsec_tags

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
          ensure
            add_waf_runtime_tags(context)
            request!
          end

          private

          def first_request?
            @first_request
          end

          def request!
            @first_request = false
          end

          def active_trace
            return unless defined?(Datadog::Tracing) && Datadog::Tracing.respond_to?(:active_span)

            Datadog::Tracing.active_trace
          end

          def add_appsec_tags
            return unless active_trace

            active_trace.set_tag('_dd.appsec.enabled', 1)
            active_trace.set_tag('_dd.runtime_family', 'ruby')
            active_trace.set_tag('_dd.appsec.waf.version', Datadog::AppSec::WAF::VERSION::BASE_STRING)

            if @processor.ruleset_info
              active_trace.set_tag('_dd.appsec.event_rules.version', @processor.ruleset_info[:version])
              if first_request?
                active_trace.set_tag('_dd.appsec.event_rules.loaded', @processor.ruleset_info[:loaded].to_f)
                active_trace.set_tag('_dd.appsec.event_rules.error_count', @processor.ruleset_info[:failed].to_f)
                active_trace.set_tag('_dd.appsec.event_rules.errors', JSON.dump(@processor.ruleset_info[:errors]))
                active_trace.keep!
              end
            end
          end

          def add_waf_runtime_tags(context)
            active_trace.set_tag('_dd.appsec.waf.timeouts', context.timeouts)
            active_trace.set_tag('_dd.appsec.waf.duration', context.time / 1000.0)
            active_trace.set_tag('_dd.appsec.waf.duration_ext', context.time_ext / 1000.0)
          end
        end
      end
    end
  end
end
