# frozen_string_literal: true

require_relative '../ext'
require_relative '../../../instrumentation/gateway'
require_relative '../reactive/resolve'
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

                watch_execute(gateway)
                watch_resolve(gateway)
              end

              def watch_execute(gateway = Instrumentation.gateway)
                require 'graphql/query/result'
                gateway.watch('graphql.execute', :appsec) do |stack, gateway_execute|
                  event = nil
                  if gateway_execute.variables[:query] == 'threat'
                    result = OpenStruct.new(
                      actions: ['block'],
                      derivatives: {},
                      events: [],
                      status: :match,
                      timeout: false,
                      total_runtime: 10000
                    )
                    event = OpenStruct.new(
                      waf_result: result,
                      request: gateway_execute,
                      actions: result.actions
                    )
                  end

                  if event && event.actions.include?('block')
                    throw Ext::QUERY_INTERRUPT,
                      ::GraphQL::Query::Result.new(
                        query: gateway_execute.query,
                        values: {
                          data: nil,
                          errors: [{
                            message: 'Blocked',
                            extensions: {
                              detail: 'This message will be customised with WAF data (execute)'
                            }
                          }]
                        }
                      )
                  end

                  ret, res = stack.call(gateway_execute.variables)

                  [ret, res]
                end
              end

              def watch_resolve(gateway = Instrumentation.gateway)
                require 'graphql/query/result'
                gateway.watch('graphql.resolve', :appsec) do |stack, gateway_resolve|
                  block = false
                  event = nil
                  scope = AppSec::Scope.active_scope

                  AppSec::Reactive::Operation.new('graphql.resolve') do |op|
                    GraphQL::Reactive::Resolve.subscribe(op, scope.processor_context) do |result|
                      event = {
                        waf_result: result,
                        trace: scope.trace,
                        span: scope.service_entry_span,
                        resolve: gateway_resolve,
                        actions: result.actions
                      }

                      if scope.service_entry_span
                        scope.service_entry_span.set_tag('appsec.blocked', 'true') if result.actions.include?('block')
                        scope.service_entry_span.set_tag('appsec.event', 'true')
                      end

                      scope.processor_context.events << event
                    end

                    block = GraphQL::Reactive::Resolve.publish(op, gateway_resolve)
                  end

                  throw Ext::QUERY_INTERRUPT, error_query(gateway_resolve) if block

                  ret, res = stack.call(gateway_resolve.arguments)

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end

              private

              def error_query(gateway_resolve)
                ::GraphQL::Query::Result.new(
                  query: gateway_resolve.query,
                  values: {
                    data: nil,
                    errors: [{
                      message: 'Blocked',
                      extensions: {
                        detail: 'This message will be customised with WAF data (resolve)'
                      }
                    }]
                  }
                )
              end
            end
          end
        end
      end
    end
  end
end
