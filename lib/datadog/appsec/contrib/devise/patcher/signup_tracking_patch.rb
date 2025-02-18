# frozen_string_literal: true

require_relative '../configuration'

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

              context = AppSec.active_context
              super do |resource|
                if !resource.persisted? || context.trace.nil? || context.span.nil?
                  yield(resource) if block_given?

                  next
                end

                id = resource.id.to_s if resource.respond_to?(:id)
                login = if resource.respond_to?(:email)
                          resource.email
                        elsif resource.respond_to?(:username)
                          resource.username
                        elsif resource.respond_to?(:login)
                          resource.login
                        else
                          # NOTE: Devise `authentication_keys` does not provide informatino
                          #       on what was used to sign up if you have unified virtual
                          #       field which combines multiple database fields.
                          #       Hence we check most possible fields one-by-one.
                          #
                          #       See: https://github.com/heartcombo/devise/wiki/How-To:-Allow-users-to-sign-in-using-their-username-or-email-address
                          # TODO: Add generic extraction based on authentication keys
                          attribute = authentication_keys.find { |attr| resource.respond_to?(attr) }
                          resource.send(attribute)
                        end

                context.trace.keep!
                context.span.set_tag('appsec.events.users.signup.usr.login', login)
                context.span.set_tag('appsec.events.users.signup.track', 'true')
                context.span.set_tag('_dd.appsec.usr.id', id)
                context.span.set_tag('_dd.appsec.usr.login', login)
                context.span.set_tag(
                  '_dd.appsec.events.users.signup.auto.mode',
                  Configuration.auto_user_instrumentation_mode
                )

                if resource.active_for_authentication?
                  context.span.set_tag('usr.id', id) unless context.span.has_tag?('usr.id')
                else
                  context.span.set_tag('appsec.events.users.signup.usr.id', id)
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
