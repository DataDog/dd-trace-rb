# frozen_string_literal: true

require_relative '../../instrumentation/gateway'

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
                context = Datadog::AppSec.active_context

                persistent_data = { 'usr.id' => user.id }
                persistent_data['usr.login'] = user.login if user.login

                result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                if result.match?
                  Datadog::AppSec::Event.tag_and_keep!(context, result)

                  context.events << {
                    waf_result: result,
                    trace: context.trace,
                    span: context.span,
                    user: user,
                    actions: result.actions
                  }

                  Datadog::AppSec::ActionsHandler.handle(result.actions)
                end

                stack.call(user)
              end
            end
          end
        end
      end
    end
  end
end
