# frozen_string_literal: true

require 'json'
require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/engine'
require_relative '../reactive/multiplex'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        module Gateway
          # Watcher for Rack gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_multiplex(gateway)
              end

              # This time we don't throw but use next
              def watch_multiplex(gateway = Instrumentation.gateway)
                gateway.watch('graphql.multiplex', :appsec) do |stack, gateway_multiplex|
                  block = false
                  event = nil
                  context = AppSec::Context.active
                  engine = AppSec::Reactive::Engine.new

                  if context
                    GraphQL::Reactive::Multiplex.subscribe(engine, context.processor_context) do |result|
                      event = {
                        waf_result: result,
                        trace: context.trace,
                        span: context.service_entry_span,
                        multiplex: gateway_multiplex,
                        actions: result.actions
                      }

                      Datadog::AppSec::Event.tag_and_keep!(context, result)
                      context.processor_context.events << event
                    end

                    block = GraphQL::Reactive::Multiplex.publish(engine, gateway_multiplex)
                  end

                  next [nil, [[:block, event]]] if block

                  stack.call(gateway_multiplex.arguments)
                end
              end
            end
          end
        end
      end
    end
  end
end
