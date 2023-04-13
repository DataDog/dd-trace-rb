require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/operation'
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
                  block = false
                  event = nil
                  waf_context = gateway_request.env['datadog.waf.context']

                  AppSec::Reactive::Operation.new('rack.request') do |op|
                    trace = active_trace
                    span = active_span

                    Rack::Reactive::Request.subscribe(op, waf_context) do |result, _block|
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

                    _result, block = Rack::Reactive::Request.publish(op, gateway_request)
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

              def watch_response(gateway = Instrumentation.gateway)
                gateway.watch('rack.response', :appsec) do |stack, gateway_response|
                  block = false
                  event = nil
                  waf_context = gateway_response.active_context

                  AppSec::Reactive::Operation.new('rack.response') do |op|
                    trace = active_trace
                    span = active_span

                    Rack::Reactive::Response.subscribe(op, waf_context) do |result, _block|
                      if result.status == :match
                        # TODO: should this hash be an Event instance instead?
                        event = {
                          waf_result: result,
                          trace: trace,
                          span: span,
                          response: gateway_response,
                          actions: result.actions
                        }

                        span.set_tag('appsec.event', 'true') if span

                        waf_context.events << event
                      end
                    end

                    _result, block = Rack::Reactive::Response.publish(op, gateway_response)
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(gateway_response.response)

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end

              def watch_request_body(gateway = Instrumentation.gateway)
                gateway.watch('rack.request.body', :appsec) do |stack, gateway_request|
                  block = false
                  event = nil
                  waf_context = gateway_request.env['datadog.waf.context']

                  AppSec::Reactive::Operation.new('rack.request.body') do |op|
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
