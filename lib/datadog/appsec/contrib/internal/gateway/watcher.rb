# typed: ignore
# frozen_string_literal: true

require_relative '../../../instrumentation/gateway'
require_relative '../../../reactive/operation'
require_relative '../reactive/set_user'
require_relative '../../../event'

module Datadog
  module AppSec
    module Contrib
      module Internal
        module Gateway
          # Watcher for Rack gateway events
          module Watcher
            class << self
              def watch
                gateway = Instrumentation.gateway

                watch_user_id(gateway)
              end

              def watch_user_id(gateway = Instrumentation.gateway)
                gateway.watch('identity.set_user', :appsec) do |stack, user_id|
                  block = false
                  event = nil
                  waf_context = ::Datadog::AppSec::Processor.current_context

                  AppSec::Reactive::Operation.new('identity.set_user') do |op|
                    trace = active_trace
                    span = active_span

                    Internal::Reactive::SetUser.subscribe(op, waf_context) do |result, _block|
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

                    _result, block = Internal::Reactive::SetUser.publish(op, user_id)
                  end


                  next [nil, [:block, event]] if block

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

                return unless defined?(::Datadog::Tracing)

                ::Datadog::Tracing.active_trace
              end

              def active_span
                # TODO: factor out tracing availability detection

                return unless defined?(::Datadog::Tracing)

                ::Datadog::Tracing.active_span
              end
            end
          end
        end
      end
    end
  end
end
