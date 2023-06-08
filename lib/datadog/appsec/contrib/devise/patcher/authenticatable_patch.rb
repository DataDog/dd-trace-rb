# frozen_string_literal: true

require_relative '../ext'
require_relative '../tracking'
require_relative '../resource'

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patcher
          # Hook in devise validate method
          module AuthenticatablePatch
            # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
            def validate(resource, &block)
              result = super
              return result unless AppSec.enabled?

              automated_track_user_events_mode = AppSec.settings.automated_track_user_events

              return result if automated_track_user_events_mode == Ext::DISABLED_MODE

              appsec_scope = Datadog::AppSec.active_scope

              return result unless appsec_scope

              devise_resource = resource ? Resource.new(resource) : nil

              event_information = {}
              user_id = nil

              if automated_track_user_events_mode == Ext::EXTENDED_MODE && devise_resource
                resource_email = devise_resource.email
                resource_username = devise_resource.username

                event_information[:email] = resource_email if resource_email
                event_information[:username] = resource_username if resource_username
              end

              user_id = devise_resource.id if devise_resource && devise_resource.id

              if result
                if user_id
                  Tracking.track_login_success(
                    appsec_scope.trace,
                    appsec_scope.service_entry_span,
                    user_id: user_id,
                    **event_information
                  )
                  Datadog.logger.debug { 'User Login Event success' }
                else
                  Tracking.track_login_success(
                    appsec_scope.trace,
                    appsec_scope.service_entry_span,
                    user_id: nil,
                    **event_information
                  )
                  Datadog.logger.debug { 'User Login Event success, but can\'t extract user ID. Tracking empty event' }
                end

                return result
              end

              if devise_resource
                Tracking.track_login_failure(
                  appsec_scope.trace,
                  appsec_scope.service_entry_span,
                  user_id: user_id,
                  user_exists: true,
                  **event_information
                )
                Datadog.logger.debug { 'User Login Event failure users exists' }
              else
                Tracking.track_login_failure(
                  appsec_scope.trace,
                  appsec_scope.service_entry_span,
                  user_id: nil,
                  user_exists: false,
                  **event_information
                )
                Datadog.logger.debug { 'User Login Event failure user do not exists' }
              end

              result
            end
            # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity
          end
        end
      end
    end
  end
end
