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
          ARBITRARY_VALUE = 'invalid'

          IDENTITY_EVENTS = %w[
            identity.sdk.set_user
            identity.sdk.login_success
            identity.sdk.login_failure
            identity.devise.login_success
            identity.devise.login_failure
            identity.devise.signup
            identity.devise.authenticated_request
          ].freeze

          LOGIN_EVENTS = {
            'identity.sdk.login_success' => 'server.business_logic.users.login.success',
            'identity.sdk.login_failure' => 'server.business_logic.users.login.failure',
            'identity.devise.login_success' => 'server.business_logic.users.login.success',
            'identity.devise.login_failure' => 'server.business_logic.users.login.failure',
          }.freeze

          class << self
            def watch
              gateway = Instrumentation.gateway

              watch_user_id(gateway)
              watch_user_login_event(gateway)
            end

            def watch_user_id(gateway = Instrumentation.gateway)
              IDENTITY_EVENTS.each do |event_name|
                gateway.watch(event_name) do |stack, user_info|
                  context = AppSec.active_context

                  if user_info[:id].nil? && user_info[:login].nil? && user_info[:session_id].nil?
                    Datadog.logger.debug { 'AppSec: skipping WAF check because no user information was provided' }
                    next stack.call(user_info)
                  end

                  persistent_data = {}
                  persistent_data['usr.id'] = user_info[:id] if user_info[:id]
                  persistent_data['usr.login'] = user_info[:login] if user_info[:login]
                  persistent_data['usr.session_id'] = user_info[:session_id] if user_info[:session_id]

                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match? || result.attributes.any?
                    context.events.push(
                      AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                    )
                  end

                  if result.match?
                    AppSec::Event.tag(context, result)
                    AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(user_info)
                end
              end
            end

            def watch_user_login_event(gateway = Instrumentation.gateway)
              LOGIN_EVENTS.each do |event_name, business_logic_key|
                gateway.watch(event_name) do |stack, user_info|
                  context = AppSec.active_context

                  persistent_data = {business_logic_key => ARBITRARY_VALUE}
                  result = context.run_waf(persistent_data, {}, Datadog.configuration.appsec.waf_timeout)

                  if result.match? || result.attributes.any?
                    context.events.push(
                      AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
                    )
                  end

                  if result.match?
                    AppSec::Event.tag(context, result)
                    AppSec::ActionsHandler.handle(result.actions)
                  end

                  stack.call(user_info)
                end
              end
            end
          end
        end
      end
    end
  end
end
