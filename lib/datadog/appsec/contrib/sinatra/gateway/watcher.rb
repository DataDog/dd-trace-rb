# frozen_string_literal: true

require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/engine'
require_relative '../../rack/reactive/request_body'
require_relative '../reactive/routed'
require_relative '../../../event'

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        module Gateway
          # Watcher for Sinatra gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request_dispatch(gateway)
                watch_request_routed(gateway)
              end

              def watch_request_dispatch(gateway = Instrumentation.gateway)
                gateway.watch('sinatra.request.dispatch', :appsec) do |stack, gateway_request|
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

              def watch_request_routed(gateway = Instrumentation.gateway)
                gateway.watch('sinatra.request.routed', :appsec) do |stack, (gateway_request, gateway_route_params)|
                  event = nil
                  context = gateway_request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
                  engine = AppSec::Reactive::Engine.new

                  Sinatra::Reactive::Routed.subscribe(engine, context) do |result|
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

                  Sinatra::Reactive::Routed.publish(engine, [gateway_request, gateway_route_params])

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
