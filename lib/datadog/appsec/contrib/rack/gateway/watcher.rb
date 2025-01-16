# frozen_string_literal: true

require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/engine'
require_relative '../reactive/request'
require_relative '../reactive/request_body'
require_relative '../reactive/response'
require_relative '../../../event'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Gateway
          # Watcher for Rack gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request(gateway)
                watch_response(gateway)
                watch_request_body(gateway)
              end

              def watch_request(gateway = Instrumentation.gateway)
                gateway.watch('rack.request', :appsec) do |stack, gateway_request|
                  event = nil
                  context = gateway_request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
                  engine = AppSec::Reactive::Engine.new

                  Rack::Reactive::Request.subscribe(engine, context) do |result|
                    if result.match?
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: context.trace,
                        span: context.span,
                        request: gateway_request,
                        actions: result.actions
                      }

                      # We want to keep the trace in case of security event
                      context.trace.keep! if context.trace
                      Datadog::AppSec::Event.tag_and_keep!(context, result)
                      context.events << event

                      result.actions.each do |action_type, action_params|
                        Datadog::AppSec::ActionHandler.handle(action_type, action_params)
                      end
                    end
                  end

                  Rack::Reactive::Request.publish(engine, gateway_request)

                  stack.call(gateway_request.request)
                end
              end

              def watch_response(gateway = Instrumentation.gateway)
                gateway.watch('rack.response', :appsec) do |stack, gateway_response|
                  event = nil
                  context = gateway_response.context
                  engine = AppSec::Reactive::Engine.new

                  Rack::Reactive::Response.subscribe(engine, context) do |result|
                    if result.match?
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: context.trace,
                        span: context.span,
                        response: gateway_response,
                        actions: result.actions
                      }

                      # We want to keep the trace in case of security event
                      context.trace.keep! if context.trace
                      Datadog::AppSec::Event.tag_and_keep!(context, result)
                      context.events << event

                      result.actions.each do |action_type, action_params|
                        Datadog::AppSec::ActionHandler.handle(action_type, action_params)
                      end
                    end
                  end

                  Rack::Reactive::Response.publish(engine, gateway_response)

                  stack.call(gateway_response.response)
                end
              end

              def watch_request_body(gateway = Instrumentation.gateway)
                gateway.watch('rack.request.body', :appsec) do |stack, gateway_request|
                  event = nil
                  context = gateway_request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
                  engine = AppSec::Reactive::Engine.new

                  Rack::Reactive::RequestBody.subscribe(engine, context) do |result|
                    if result.match?
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: context.trace,
                        span: context.span,
                        request: gateway_request,
                        actions: result.actions
                      }

                      # We want to keep the trace in case of security event
                      context.trace.keep! if context.trace
                      Datadog::AppSec::Event.tag_and_keep!(context, result)
                      context.events << event

                      result.actions.each do |action_type, action_params|
                        Datadog::AppSec::ActionHandler.handle(action_type, action_params)
                      end
                    end
                  end

                  Rack::Reactive::RequestBody.publish(engine, gateway_request)

                  stack.call(gateway_request.request)
                end
              end
            end
          end
        end
      end
    end
  end
end
