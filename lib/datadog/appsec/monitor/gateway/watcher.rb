# frozen_string_literal: true

require_relative '../../event'
require_relative '../../security_event'
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
                context = AppSec.active_context

                if user.id.nil? && user.login.nil? && user.session_id.nil?
                  Datadog.logger.debug { 'AppSec: skipping WAF check because no user information was provided' }
                  next stack.call(user)
                end

                persistent_data = {}
                persistent_data['usr.id'] = user.id if user.id
                persistent_data['usr.login'] = user.login if user.login
                persistent_data['usr.session_id'] = user.session_id if user.session_id

                result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                if result.match? || !result.derivatives.empty?
                  context.events.push(
                    AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                  )
                end

                if result.match?
                  AppSec::Event.tag_and_keep!(context, result)
                  AppSec::ActionsHandler.handle(result.actions)
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
