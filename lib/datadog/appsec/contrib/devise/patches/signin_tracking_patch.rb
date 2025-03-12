# frozen_string_literal: true

require_relative '../configuration'
require_relative '../data_extractor'

module Datadog
  module AppSec
    module Contrib
      module Devise
        module Patches
          # A patch for Devise::Authenticatable strategy with tracking functionality
          module SigninTrackingPatch
            def validate(resource, &block)
              result = super

              return result unless AppSec.enabled?
              return result if @_datadog_appsec_skip_track_login_event
              return result unless Configuration.auto_user_instrumentation_enabled?
              return result unless AppSec.active_context

              context = AppSec.active_context
              if context.trace.nil? || context.span.nil?
                Datadog.logger.debug { 'AppSec: unable to track signin events, due to missing trace or span' }
                return result
              end

              context.trace.keep!

              if result
                record_successfull_signin(context, resource)

                return result
              end

              record_failed_signin(context, resource)
              result
            end

            private

            def record_successfull_signin(context, resource)
              extractor = DataExtractor.new(Configuration.auto_user_instrumentation_mode)

              id = extractor.extract_id(resource)
              login = extractor.extract_login(authentication_hash) || extractor.extract_login(resource)

              if id
                context.span['_dd.appsec.usr.id'] = id

                unless context.span.has_tag?('usr.id')
                  context.span['usr.id'] = id
                  AppSec::Instrumentation.gateway.push(
                    'identity.set_user', AppSec::Instrumentation::Gateway::User.new(id)
                  )
                end
              end

              context.span['appsec.events.users.login.success.usr.login'] ||= login
              context.span['appsec.events.users.login.success.track'] = 'true'
              context.span['_dd.appsec.usr.login'] = login
              context.span['_dd.appsec.events.users.login.success.auto.mode'] = Configuration.auto_user_instrumentation_mode
            end

            def record_failed_signin(context, resource)
              extractor = DataExtractor.new(Configuration.auto_user_instrumentation_mode)

              context.span['appsec.events.users.login.failure.track'] = 'true'
              context.span['_dd.appsec.events.users.login.failure.auto.mode'] = Configuration.auto_user_instrumentation_mode

              unless resource
                login = extractor.extract_login(authentication_hash)

                context.span['_dd.appsec.usr.login'] = login
                context.span['appsec.events.users.login.failure.usr.login'] ||= login
                context.span['appsec.events.users.login.failure.usr.exists'] ||= 'false'

                return
              end

              id = extractor.extract_id(resource)
              login = extractor.extract_login(authentication_hash) || extractor.extract_login(resource)

              if id
                context.span['_dd.appsec.usr.id'] = id
                context.span['appsec.events.users.login.failure.usr.id'] ||= id
              end

              context.span['_dd.appsec.usr.login'] = login
              context.span['appsec.events.users.login.failure.usr.login'] ||= login
              context.span['appsec.events.users.login.failure.usr.exists'] ||= 'true'
            end
          end
        end
      end
    end
  end
end
