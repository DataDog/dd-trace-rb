# frozen_string_literal: true

require_relative '../tracking'
require_relative '../resource'
require_relative '../event'

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patcher
          # Hook in devise registration controller
          module RegistrationControllerPatch
            def create
              return super unless AppSec.enabled?

              track_user_events_configuration = Datadog.configuration.appsec.track_user_events

              return super unless track_user_events_configuration.enabled

              automated_track_user_events_mode = track_user_events_configuration.mode

              appsec_context = Datadog::AppSec.active_context
              return super unless appsec_context

              super do |resource|
                if resource.persisted?
                  devise_resource = Resource.new(resource)

                  event_information = Event.new(devise_resource, automated_track_user_events_mode)

                  if event_information.user_id
                    Datadog.logger.debug { 'User Signup Event' }
                  else
                    Datadog.logger.warn { 'User Signup Event, but can\'t extract user ID. Tracking empty event' }
                  end

                  Tracking.track_signup(
                    appsec_context.trace,
                    appsec_context.span,
                    user_id: event_information.user_id,
                    **event_information.to_h
                  )
                end

                yield resource if block_given?
              end
            end

            private

            # NOTE: DEV-3 replace method use with `auto_user_instrumentation.enabled?`
            def auto_user_instrumentation_enabled?
              Datadog.configuration.appsec.auto_user_instrumentation.enabled? &&
                Datadog.configuration.appsec.track_user_events.enabled
            end

            # NOTE: DEV-3 replace method use with `auto_user_instrumentation.mode`
            def auto_user_instrumentation_mode
              case Datadog.configuration.appsec.track_user_events.mode
              when Configuration::Settings::SAFE_TRACK_USER_EVENTS_MODE
                Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE
              when Configuration::Settings::EXTENDED_TRACK_USER_EVENTS_MODE
                Configuration::Settings::IDENTIFICATION_AUTO_USER_INSTRUMENTATION_MODE
              else
                Datadog.configuration.appsec.auto_user_instrumentation.mode
              end
            end
          end
        end
      end
    end
  end
end
