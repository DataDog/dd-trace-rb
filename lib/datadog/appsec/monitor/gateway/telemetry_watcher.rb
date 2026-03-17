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

              watch_set_user(gateway)
              watch_login_failure(gateway)
            end

            def watch_set_user(gateway = Instrumentation.gateway)
              gateway.watch('identity.set_user') do |stack, user_info|
                event_type = user_info[:event_type]
                report_missing_user_telemetry(user_info, event_type) if event_type

                stack.call(user_info)
              end
            end

            def watch_login_failure(gateway = Instrumentation.gateway)
              gateway.watch('identity.login_failure') do |stack, user_info|
                report_missing_user_telemetry(user_info, 'login_failure')

                stack.call(user_info)
              end
            end

            private

            def report_missing_user_telemetry(user_info, event_type)
              tags = {framework: user_info[:framework], event_type: event_type}

              missing_login = user_info[:login].nil?
              missing_id = user_info[:id].nil?

              if missing_login && event_type != 'authenticated_request'
                AppSec.telemetry.inc(
                  Ext::TELEMETRY_METRICS_NAMESPACE,
                  'instrum.user_auth.missing_user_login',
                  1,
                  tags: tags,
                )
              end

              if missing_id && (event_type == 'authenticated_request' || missing_login)
                AppSec.telemetry.inc(
                  Ext::TELEMETRY_METRICS_NAMESPACE,
                  'instrum.user_auth.missing_user_id',
                  1,
                  tags: tags,
                )
              end
            end
          end
        end
      end
    end
  end
end
