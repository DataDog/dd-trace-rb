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
                  context = gateway_request.env[Datadog::AppSec::Ext::SCOPE_KEY]
                  engine = AppSec::Reactive::Engine.new

                  Rails::Reactive::Action.subscribe(engine, context.processor_context) do |result|
                    if result.status == :match
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: context.trace,
                        span: context.service_entry_span,
                        request: gateway_request,
                        actions: result.actions
                      }

                      # We want to keep the trace in case of security event
                      context.trace.keep! if context.trace
                      Datadog::AppSec::Event.tag_and_keep!(context, result)
                      context.processor_context.events << event
                    end
                  end

                  block = Rails::Reactive::Action.publish(engine, gateway_request)
                  next [nil, [[:block, event]]] if block

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
