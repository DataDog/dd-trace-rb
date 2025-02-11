# frozen_string_literal: true

require_relative '../configuration'
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
              return result if @_datadog_appsec_skip_track_login_event
              return result unless Configuration.auto_user_instrumentation_enabled?
              return result unless AppSec.active_context

              devise_resource = resource ? Resource.new(resource) : nil
              event_information = Event.new(devise_resource, Configuration.auto_user_instrumentation_mode)

              if result
                if event_information.user_id
                  Datadog.logger.debug { 'AppSec: User successful login event' }
                else
                  Datadog.logger.debug do
                    "AppSec: User successful login event, but can't extract user ID. Tracking empty event"
                  end
                end

                Tracking.track_login_success(
                  AppSec.active_context.trace,
                  AppSec.active_context.span,
                  user_id: event_information.user_id,
                  **event_information.to_h
                )

                return result
              end

              user_exists = nil

              if resource
                user_exists = true
                Datadog.logger.debug { 'AppSec: User failed login event, but user exists' }
              else
                user_exists = false
                Datadog.logger.debug { 'AppSec: User failed login event and user does not exist' }
              end

              Tracking.track_login_failure(
                AppSec.active_context.trace,
                AppSec.active_context.span,
                user_id: event_information.user_id,
                user_exists: user_exists,
                **event_information.to_h
              )

              result
            end
            # rubocop:enable Metrics/MethodLength
          end
        end
      end
    end
  end
end
