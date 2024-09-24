# frozen_string_literal: true

require 'json'
require_relative '../../../instrumentation/gateway'
require_relative '../reactive/multiplex'
require_relative '../../../reactive/operation'

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

                  scope = AppSec::Scope.active_scope

                  if scope
                    AppSec::Reactive::Operation.new('graphql.multiplex') do |op|
                      GraphQL::Reactive::Multiplex.subscribe(op, scope.processor_context) do |result|
                        event = {
                          waf_result: result,
                          trace: scope.trace,
                          span: scope.service_entry_span,
                          multiplex: gateway_multiplex,
                          actions: result.actions
                        }

                        if scope.service_entry_span
                          scope.service_entry_span.set_tag('appsec.blocked', 'true') if result.actions.include?('block')
                          scope.service_entry_span.set_tag('appsec.event', 'true')
                        end

                        scope.processor_context.events << event
                      end

                      block = GraphQL::Reactive::Multiplex.publish(op, gateway_multiplex)
                    end
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(gateway_multiplex.arguments)

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
