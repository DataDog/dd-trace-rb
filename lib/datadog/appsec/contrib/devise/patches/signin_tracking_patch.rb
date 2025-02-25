# frozen_string_literal: true

require_relative '../configuration'

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patches
          # Hook in devise validate method
          module SigninTrackingPatch
            def validate(resource, &block)
              result = super

              return result unless AppSec.enabled?
              return result if @_datadog_appsec_skip_track_login_event
              return result unless Configuration.auto_user_instrumentation_enabled?
              return result unless AppSec.active_context

              context = AppSec.active_context
              context.trace.keep!

              # Success
              if result
                id = resource.id.to_s if resource.respond_to?(:id) && !resource.id.nil?
                login = if resource.respond_to?(:email)
                          resource.email
                        elsif resource.respond_to?(:username)
                          resource.username
                        elsif resource.respond_to?(:login)
                          resource.login
                        else
                          attribute = authentication_keys.find { |attr| resource.respond_to?(attr) }
                          resource.send(attribute)
                        end

                if id
                  context.span.set_tag('usr.id', id) unless context.span.has_tag?('usr.id')
                  context.span.set_tag('_dd.appsec.usr.id', id)
                end

                unless context.span.has_tag?('appsec.events.users.login.success.usr.login')
                  context.span.set_tag('appsec.events.users.login.success.usr.login', login)
                end

                context.span.set_tag('appsec.events.users.login.success.track', 'true')
                context.span.set_tag('_dd.appsec.usr.login', login)
                context.span.set_tag(
                  '_dd.appsec.events.users.login.success.auto.mode',
                  Configuration.auto_user_instrumentation_mode
                )

                return result
              end

              # Failure

              context.span.set_tag('appsec.events.users.login.failure.track', 'true')
              context.span.set_tag(
                '_dd.appsec.events.users.login.failure.auto.mode',
                Configuration.auto_user_instrumentation_mode
              )

              if resource
                id = resource.id.to_s if resource.respond_to?(:id) && !resource.id.nil?
                login = if resource.respond_to?(:email)
                          resource.email
                        elsif resource.respond_to?(:username)
                          resource.username
                        elsif resource.respond_to?(:login)
                          resource.login
                        else
                          attribute = authentication_keys.find { |attr| resource.respond_to?(attr) }
                          resource.send(attribute)
                        end

                if id
                  context.span.set_tag('_dd.appsec.usr.id', id)
                  unless context.span.has_tag?('appsec.events.users.login.failure.usr.id')
                    context.span.set_tag('appsec.events.users.login.failure.usr.id', id)
                  end
                end

                context.span.set_tag('_dd.appsec.usr.login', login)
                context.span.set_tag('appsec.events.users.login.failure.usr.exists', 'true')

                unless context.span.has_tag?('appsec.events.users.login.failure.usr.login')
                  context.span.set_tag('appsec.events.users.login.failure.usr.login', login)
                end
              else
                login = authentication_hash[:email] || authentication_hash[:username] ||
                  authentication_hash[:login] || authentication_hash.values[0]

                context.span.set_tag('_dd.appsec.usr.login', login)
                context.span.set_tag('appsec.events.users.login.failure.usr.exists', 'false')

                unless context.span.has_tag?('appsec.events.users.login.failure.usr.login')
                  context.span.set_tag('appsec.events.users.login.failure.usr.login', login)
                end
              end

              result
            end
          end
        end
      end
    end
  end
end
