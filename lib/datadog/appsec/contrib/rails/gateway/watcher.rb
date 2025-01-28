# frozen_string_literal: true

require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/engine'
require_relative '../reactive/action'
require_relative '../../../event'

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Gateway
          # Watcher for Rails gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_request_action(gateway)
              end

              def watch_request_action(gateway = Instrumentation.gateway)
                gateway.watch('rails.request.action', :appsec) do |stack, gateway_request|
                  event = nil
                  context = gateway_request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
                  engine = AppSec::Reactive::Engine.new

                  Rails::Reactive::Action.subscribe(engine, context) do |result|
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

                      Datadog::AppSec::ActionsHandler.handle(result.actions)
                    end
                  end

                  Rails::Reactive::Action.publish(engine, gateway_request)

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
