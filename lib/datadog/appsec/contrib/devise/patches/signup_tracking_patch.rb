# frozen_string_literal: true

require_relative '../configuration'
require_relative '../data_extractor'

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patches
          # A patch for Devise::RegistrationsController with tracking functionality
          module SignupTrackingPatch
            def create
              return super unless AppSec.enabled?
              return super unless Configuration.auto_user_instrumentation_enabled?
              return super unless AppSec.active_context

              super do |resource|
                context = AppSec.active_context

                if !resource.persisted? || context.trace.nil? || context.span.nil?
                  yield(resource) if block_given?

                  next
                end

                context.trace.keep!
                record_successfull_signup(context, resource)

                yield resource if block_given?
              end
            end

            private

            def record_successfull_signup(context, resource)
              extractor = DataExtractor.new(Configuration.auto_user_instrumentation_mode)

              id = extractor.extract_id(resource)
              login = extractor.extract_login(resource_params) || extractor.extract_login(resource)

              context.span['appsec.events.users.signup.track'] = 'true'
              context.span['_dd.appsec.usr.login'] = login
              context.span['_dd.appsec.events.users.signup.auto.mode'] = Configuration.auto_user_instrumentation_mode
              context.span['appsec.events.users.signup.usr.login'] ||= login

              return if id.nil?

              context.span.set_tag('_dd.appsec.usr.id', id)
              if resource.active_for_authentication?
                context.span['usr.id'] ||= id
              else
                context.span['appsec.events.users.signup.usr.id'] ||= id
              end
            end
          end
        end
      end
    end
  end
end
