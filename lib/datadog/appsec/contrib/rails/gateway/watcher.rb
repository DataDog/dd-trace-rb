require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/operation'
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
                gateway.watch('rails.request.action', :appsec) do |stack, request|
                  block = false
                  event = nil
                  waf_context = request.env['datadog.waf.context']

                  AppSec::Reactive::Operation.new('rails.request.action') do |op|
                    trace = active_trace
                    span = active_span

                    Rails::Reactive::Action.subscribe(op, waf_context) do |result, _block|
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

                    _result, block = Rails::Reactive::Action.publish(op, request)
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
