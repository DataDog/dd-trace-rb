# frozen_string_literal: true

require_relative '../../instrumentation/gateway'
require_relative '../../reactive/operation'
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
                block = false
                event = nil
                scope = Datadog::AppSec.active_scope

                AppSec::Reactive::Operation.new('identity.set_user') do |op|
                  Monitor::Reactive::SetUser.subscribe(op, scope.processor_context) do |result|
                    if result.status == :match
                      # TODO: should this hash be an Event instance instead?
                      event = {
                        waf_result: result,
                        trace: scope.trace,
                        span: scope.service_entry_span,
                        user: user,
                        actions: result.actions
                      }

                      # We want to keep the trace in case of security event
                      scope.trace.keep! if scope.trace
                      Datadog::AppSec::Event.tag_and_keep!(scope, result)
                      scope.processor_context.events << event
                    end
                  end

                  block = Monitor::Reactive::SetUser.publish(op, user)
                end

                throw(Datadog::AppSec::Ext::INTERRUPT, [nil, [[:block, event]]]) if block

                ret, res = stack.call(user)

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
