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
          # Hook in devise registration controller
          module SignupTrackingPatch
            def create
              return super unless AppSec.enabled?
              return super unless Configuration.auto_user_instrumentation_enabled?
              return super unless AppSec.active_context

              super do |resource|
                if resource.persisted?
                  devise_resource = Resource.new(resource)
                  event_information = Event.new(devise_resource, Configuration.auto_user_instrumentation_mode)

                  if event_information.user_id
                    Datadog.logger.debug { 'AppSec: User signup event' }
                  else
                    Datadog.logger.warn { "AppSec: User signup event, but can't extract user ID. Tracking empty event" }
                  end

                  Tracking.track_signup(
                    AppSec.active_context.trace,
                    AppSec.active_context.span,
                    user_id: event_information.user_id,
                    **event_information.to_h
                  )
                end

                yield resource if block_given?
              end
            end
          end
        end
      end
    end
  end
end
