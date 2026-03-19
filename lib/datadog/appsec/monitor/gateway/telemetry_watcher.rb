# frozen_string_literal: true

require_relative '../../ext'
require_relative '../../instrumentation/gateway'

module Datadog
  module AppSec
    module Monitor
      module Gateway
        # Telemetry watcher for user auth instrumentation events
        module TelemetryWatcher
          class << self
            def watch
              gateway = Instrumentation.gateway

              watch_user_lifecycle(gateway)
              watch_authenticated_request(gateway)
            end

            def watch_user_lifecycle(gateway = Instrumentation.gateway)
              %w[
                identity.devise.login_success
                identity.devise.login_failure
                identity.devise.signup
              ].each do |event_name|
                gateway.watch(event_name) do |stack, user_info|
                  _, framework, event_type = event_name.split('.')
                  tags = {framework: framework, event_type: event_type}

                  if user_info[:login].nil?
                    AppSec.telemetry.inc(
                      Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_login', 1, tags: tags
                    )
                  end

                  if user_info[:id].nil? && user_info[:login].nil?
                    AppSec.telemetry.inc(
                      Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_id', 1, tags: tags
                    )
                  end

                  stack.call(user_info)
                end
              end
            end

            def watch_authenticated_request(gateway = Instrumentation.gateway)
              gateway.watch('identity.devise.authenticated_request') do |stack, user_info|
                tags = {framework: 'devise', event_type: 'authenticated_request'}

                if user_info[:id].nil?
                  AppSec.telemetry.inc(
                    Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_id', 1, tags: tags
                  )
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
