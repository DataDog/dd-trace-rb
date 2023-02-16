# typed: ignore

require_relative '../../../ext'
require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/operation'
require_relative '../reactive/request'
require_relative '../reactive/request_body'
require_relative '../reactive/response'
require_relative '../reactive/set_user'
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
                watch_user_id(gateway)
              end

              def watch_request(gateway = Instrumentation.gateway)
                gateway.watch('rack.request', :appsec) do |stack, request|
                  block = false
                  event = nil
                  waf_context = request.env['datadog.waf.context']

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
                          request: request,
                          actions: result.actions
                        }

                        span.set_tag('appsec.event', 'true') if span

                        waf_context.events << event
                      end
                    end

                    _result, block = Rack::Reactive::Request.publish(op, request)
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = nil

                  _, catched_request = catch(Datadog::AppSec::Ext::REQUEST_INTERRUPT) do
                    ret, res = stack.call(request)
                  end

                  next [nil, catched_request] if catched_request

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end

              def watch_response(gateway = Instrumentation.gateway)
                gateway.watch('rack.response', :appsec) do |stack, response|
                  block = false
                  event = nil
                  waf_context = response.instance_eval { @waf_context }

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
                          response: response,
                          actions: result.actions
                        }

                        span.set_tag('appsec.event', 'true') if span

                        waf_context.events << event
                      end
                    end

                    _result, block = Rack::Reactive::Response.publish(op, response)
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(response)

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end

              def watch_request_body(gateway = Instrumentation.gateway)
                gateway.watch('rack.request.body', :appsec) do |stack, request|
                  block = false
                  event = nil
                  waf_context = request.env['datadog.waf.context']

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
                          request: request,
                          actions: result.actions
                        }

                        span.set_tag('appsec.event', 'true') if span

                        waf_context.events << event
                      end
                    end

                    _result, block = Rack::Reactive::RequestBody.publish(op, request)
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(request)

                  if event
                    res ||= []
                    res << [:monitor, event]
                  end

                  [ret, res]
                end
              end

              def watch_user_id(gateway = Instrumentation.gateway)
                gateway.watch('identity.set_user', :appsec) do |stack, user_id|
                  block = false
                  event = nil
                  waf_context = Datadog::AppSec::Processor.current_context

                  AppSec::Reactive::Operation.new('identity.set_user') do |op|
                    trace = active_trace
                    span = active_span

                    Rack::Reactive::SetUser.subscribe(op, waf_context) do |result, _block|
                      if result.status == :match
                        # TODO: should this hash be an Event instance instead?
                        event = {
                          waf_result: result,
                          trace: trace,
                          span: span,
                          user_id: user_id,
                          actions: result.actions
                        }

                        span.set_tag('appsec.event', 'true') if span

                        waf_context.events << event
                      end
                    end

                    _result, block = Rack::Reactive::SetUser.publish(op, user_id)
                  end

                  next [nil, [[:block, event]]] if block

                  ret, res = stack.call(user_id)

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
