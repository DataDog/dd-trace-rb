# frozen_string_literal: true

require_relative '../tracking'
require_relative '../resource'

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patcher
          # Hook in devise registration controller
          module RegistrationControllerPatch
            def create
              return super unless AppSec.enabled?

              return unless Datadog.configuration.appsec.track_user_events.enabled

              automated_track_user_events_mode = Datadog.configuration.appsec.track_user_events.mode

              appsec_scope = Datadog::AppSec.active_scope
              return super unless appsec_scope

              super do |resource|
                if resource.persisted?
                  devise_resource = Resource.new(resource)

                  event_information = {}
                  user_id = devise_resource.id if devise_resource && devise_resource.id

                  if automated_track_user_events_mode == Patcher::EXTENDED_MODE
                    resource_email = devise_resource.email
                    resource_username = devise_resource.username

                    event_information[:email] = resource_email if resource_email
                    event_information[:username] = resource_username if resource_username
                  end

                  if user_id
                    Tracking.track_signup(
                      appsec_scope.trace,
                      appsec_scope.service_entry_span,
                      user_id: user_id,
                      **event_information
                    )
                    Datadog.logger.debug { 'User Signup Event' }
                  else
                    Tracking.track_signup(
                      appsec_scope.trace,
                      appsec_scope.service_entry_span,
                      user_id: nil,
                      **event_information
                    )
                    Datadog.logger.warn { 'User Signup Event, but can\'t extract user ID. Tracking empty event' }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
