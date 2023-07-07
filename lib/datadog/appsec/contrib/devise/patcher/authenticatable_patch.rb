# frozen_string_literal: true

require_relative '../tracking'
require_relative '../resource'
require_relative '../event'

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patcher
          # Hook in devise validate method
          module AuthenticatablePatch
            # rubocop:disable Metrics/MethodLength
            def validate(resource, &block)
              result = super
              return result unless AppSec.enabled?

              track_user_events_configuration = Datadog.configuration.appsec.track_user_events

              return result unless track_user_events_configuration.enabled

              automated_track_user_events_mode = track_user_events_configuration.mode

              appsec_scope = Datadog::AppSec.active_scope

              return result unless appsec_scope

              devise_resource = resource ? Resource.new(resource) : nil

              event_information = Event.new(devise_resource, automated_track_user_events_mode)

              if result
                if event_information.user_id
                  Tracking.track_login_success(
                    appsec_scope.trace,
                    appsec_scope.service_entry_span,
                    user_id: event_information.user_id,
                    **event_information.to_h
                  )
                  Datadog.logger.debug { 'User Login Event success' }
                else
                  Tracking.track_login_success(
                    appsec_scope.trace,
                    appsec_scope.service_entry_span,
                    user_id: nil,
                    **event_information.to_h
                  )
                  Datadog.logger.debug { 'User Login Event success, but can\'t extract user ID. Tracking empty event' }
                end

                return result
              end

              if resource
                Tracking.track_login_failure(
                  appsec_scope.trace,
                  appsec_scope.service_entry_span,
                  user_id: event_information.user_id,
                  user_exists: true,
                  **event_information.to_h
                )
                Datadog.logger.debug { 'User Login Event failure users exists' }
              else
                Tracking.track_login_failure(
                  appsec_scope.trace,
                  appsec_scope.service_entry_span,
                  user_id: nil,
                  user_exists: false,
                  **event_information.to_h
                )
                Datadog.logger.debug { 'User Login Event failure user do not exists' }
              end

              result
            end
            # rubocop:enable Metrics/MethodLength
          end
        end
      end
    end
  end
end
