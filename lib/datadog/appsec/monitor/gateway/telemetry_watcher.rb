# frozen_string_literal: true

require_relative '../../instrumentation/gateway'
require_relative 'watcher'

module Datadog
  module AppSec
    module Monitor
      module Gateway
        # Watcher for user auth telemetry events
        module TelemetryWatcher
          EVENT_TYPE_MAP = {
            Watcher::EVENT_LOGIN_SUCCESS => 'login_success',
            Watcher::EVENT_LOGIN_FAILURE => 'login_failure',
            Watcher::EVENT_SIGNUP => 'signup',
            Watcher::EVENT_AUTHENTICATED_REQUEST => 'authenticated_request',
          }.freeze

          class << self
            def watch
              gateway = Instrumentation.gateway

              watch_user_lifecycle_telemetry(gateway)
            end

            def watch_user_lifecycle_telemetry(gateway = Instrumentation.gateway)
              gateway.watch('appsec.events.user_lifecycle') do |stack, lifecycle_event|
                event_type = EVENT_TYPE_MAP[lifecycle_event[:event]]

                if event_type && !lifecycle_event[:has_user_login]
                  tags = {event_type: event_type, framework: lifecycle_event[:framework]}

                  AppSec.telemetry.inc(
                    AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_login', 1, tags: tags
                  )

                  unless lifecycle_event[:has_user_id]
                    AppSec.telemetry.inc(
                      AppSec::Ext::TELEMETRY_METRICS_NAMESPACE, 'instrum.user_auth.missing_user_id', 1, tags: tags
                    )
                  end
                end

                stack.call(lifecycle_event)
              end
            end
          end
        end
      end
    end
  end
end
