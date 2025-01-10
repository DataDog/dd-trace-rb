# frozen_string_literal: true

require_relative '../../instrumentation/gateway'
require_relative '../../reactive/engine'
require_relative '../reactive/set_user'

module Datadog
  module AppSec
    module Monitor
      module Gateway
        # Watcher for Apssec internal events
        module Watcher
          class << self
            def watch
              gateway = Instrumentation.gateway

              watch_user_id(gateway)
            end

            def watch_user_id(gateway = Instrumentation.gateway)
              gateway.watch('identity.set_user', :appsec) do |stack, user|
                event = nil
                context = Datadog::AppSec.active_context
                engine = AppSec::Reactive::Engine.new

                Monitor::Reactive::SetUser.subscribe(engine, context.processor_context) do |result|
                  if result.status == :match
                    # TODO: should this hash be an Event instance instead?
                    event = {
                      waf_result: result,
                      trace: context.trace,
                      span: context.span,
                      user: user,
                      actions: result.actions
                    }

                    # We want to keep the trace in case of security event
                    context.trace.keep! if context.trace
                    Datadog::AppSec::Event.tag_and_keep!(context, result)
                    context.processor_context.events << event
                  end
                end

                block = Monitor::Reactive::SetUser.publish(engine, user)
                throw(Datadog::AppSec::Ext::INTERRUPT, [nil, [[:block, event]]]) if block

                stack.call(user)
              end
            end
          end
        end
      end
    end
  end
end
