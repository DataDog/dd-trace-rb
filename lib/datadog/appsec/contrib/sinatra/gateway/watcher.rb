require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/operation'
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
                  block = false
                  event = nil
                  waf_context = gateway_request.env['datadog.waf.context']

                  AppSec::Reactive::Operation.new('sinatra.request.dispatch') do |op|
                    trace = active_trace
                    span = active_span

                    Rack::Reactive::RequestBody.subscribe(op, waf_context) do |result, _block|
                      if result.status == :match
                        # TODO: should this hash be an Event instance instead?
                        event = {
                          waf_result: result,
                          trace: trace,
                          span: span,
                          request: gateway_request,
                          actions: result.actions
                        }

                        span.set_tag('appsec.event', 'true') if span

                        waf_context.events << event
                      end
                    end

                    _result, block = Rack::Reactive::RequestBody.publish(op, gateway_request)
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(gateway_request.request)

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end

              def watch_request_routed(gateway = Instrumentation.gateway)
                gateway.watch('sinatra.request.routed', :appsec) do |stack, (gateway_request, gateway_route_params)|
                  block = false
                  event = nil
                  waf_context = gateway_request.env['datadog.waf.context']

                  AppSec::Reactive::Operation.new('sinatra.request.routed') do |op|
                    trace = active_trace
                    span = active_span

                    Sinatra::Reactive::Routed.subscribe(op, waf_context) do |result, _block|
                      if result.status == :match
                        # TODO: should this hash be an Event instance instead?
                        event = {
                          waf_result: result,
                          trace: trace,
                          span: span,
                          request: gateway_request,
                          actions: result.actions
                        }

                        span.set_tag('appsec.event', 'true') if span

                        waf_context.events << event
                      end
                    end

                    _result, block = Sinatra::Reactive::Routed.publish(op, [gateway_request, gateway_route_params])
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(gateway_request.request)

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end

              private

              def active_trace
                # TODO: factor out tracing availability detection

                return unless defined?(Datadog::Tracing)

                Datadog::Tracing.active_trace
              end

              def active_span
                # TODO: factor out tracing availability detection

                return unless defined?(Datadog::Tracing)

                Datadog::Tracing.active_span
              end
            end
          end
        end
      end
    end
  end
end
