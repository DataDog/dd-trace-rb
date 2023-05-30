# frozen_string_literal: true

require_relative '../patcher'
require_relative 'resource'
require_relative 'ext'
require_relative '../../../kit/appsec/events'

module Datadog
  module AppSec
    module Contrib
      module Devise
        AUTOMATED_USER_EVENT_TAGGING_BLOCK = proc do |trace, event|
          trace.set_tag("_dd.appsec.events.#{event}.auto.mode", AppSec.settings.automated_track_user_events)
        end

        private_constant :AUTOMATED_USER_EVENT_TAGGING_BLOCK

        # Hook in devise validate method
        module AuthenticablePatch
          # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity
          def validate(resource, &block)
            result = super
            return result unless AppSec.enabled?
            return result if AppSec.settings.automated_track_user_events == Ext::DISABLED_MODE

            active_trace = defined?(Datadog::Tracing) && Datadog::Tracing.active_trace

            return result unless active_trace

            devise_resource = resource ? Resource.new(resource) : nil

            event_information = {}
            user_id = nil

            if AppSec.settings.automated_track_user_events == Ext::EXTENDED_MODE && devise_resource
              resource_email = devise_resource.email
              resource_username = devise_resource.username

              event_information[:email] = resource_email if resource_email
              event_information[:username] = resource_username if resource_username
            end

            user_id = devise_resource.id if devise_resource && devise_resource.id

            if result
              if user_id
                Datadog::Kit::AppSec::Events.track_login_success(
                  active_trace,
                  user: { id: user_id.to_s },
                  **event_information,
                  &AUTOMATED_USER_EVENT_TAGGING_BLOCK
                )
                Datadog.logger.debug { 'User Login Event success' }
              else
                Datadog.logger.warn { 'User Login Event success, but can\'t extract user ID. No event emitted' }
              end

              return result
            end

            if devise_resource
              Datadog::Kit::AppSec::Events.track_login_failure(
                active_trace,
                user_id: user_id,
                user_exists: true,
                **event_information,
                &AUTOMATED_USER_EVENT_TAGGING_BLOCK
              )
              Datadog.logger.debug { 'User Login Event failure users exists' }
            else
              Datadog::Kit::AppSec::Events.track_login_failure(
                active_trace,
                user_id: nil,
                user_exists: false,
                **event_information,
                &AUTOMATED_USER_EVENT_TAGGING_BLOCK
              )
              Datadog.logger.debug { 'User Login Event failure users do not exists' }
            end

            result
          end
          # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity
        end

        # Hook in devise registration controller
        module ResgistrationControllerPatch
          def create
            return super unless AppSec.enabled?
            return super if AppSec.settings.automated_track_user_events == Ext::DISABLED_MODE

            active_trace = defined?(Datadog::Tracing) && Datadog::Tracing.active_trace
            return super unless active_trace

            super do |resource|
              if resource.persisted?
                devise_resource = Resource.new(resource)

                event_information = {}
                user_id = devise_resource.id if devise_resource && devise_resource.id

                if AppSec.settings.automated_track_user_events == Ext::EXTENDED_MODE
                  resource_email = devise_resource.email
                  resource_username = devise_resource.username

                  event_information[:email] = resource_email if resource_email
                  event_information[:username] = resource_username if resource_username
                end

                if user_id
                  Kit::AppSec::Events.track_signup(
                    active_trace,
                    user: { id: user_id.to_s },
                    **event_information,
                    &AUTOMATED_USER_EVENT_TAGGING_BLOCK
                  )
                  Datadog.logger.debug { 'User Signup Event' }
                else
                  Datadog.logger.warn { 'User Signup Event, but can\'t extract user ID. No event emitted' }
                end
              end
            end
          end
        end

        # Patcher for AppSec on Devise
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            patch_authenticable_strategy
            patch_registration_controller

            Patcher.instance_variable_set(:@patched, true)
          end

          def patch_authenticable_strategy
            ::Devise::Strategies::Authenticatable.prepend(AuthenticablePatch)
          end

          def patch_registration_controller
            ::ActiveSupport.on_load(:after_initialize) do
              ::Devise::RegistrationsController.prepend(ResgistrationControllerPatch)
            end
          end
        end
      end
    end
  end
end
