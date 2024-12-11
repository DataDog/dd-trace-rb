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
                  scope = gateway_request.env[Datadog::AppSec::Ext::SCOPE_KEY]
                  engine = AppSec::Reactive::Engine.new

                  Rails::Reactive::Action.subscribe(engine, scope.processor_context) do |result|
                    if result.status == :match
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: scope.trace,
                        span: scope.service_entry_span,
                        request: gateway_request,
                        actions: result.actions
                      }

                      # We want to keep the trace in case of security event
                      scope.trace.keep! if scope.trace
                      Datadog::AppSec::Event.tag_and_keep!(scope, result)
                      scope.processor_context.events << event
                    end
                  end

                  block = Rails::Reactive::Action.publish(engine, gateway_request)
                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(gateway_request.request)

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end
            end
          end
        end
      end
    end
  end
end
