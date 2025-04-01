# frozen_string_literal: true

require_relative 'ext'
require_relative '../../anonymizer'

module Datadog
  module AppSec
    module Contrib
      module Devise
        # A Rack middleware capable of tracking currently signed user
        class TrackingMiddleware
          WARDEN_KEY = 'warden'

          def initialize(app)
            @app = app
            @devise_session_scope_keys = {}
          end

          def call(env)
            return @app.call(env) unless AppSec.enabled?
            return @app.call(env) unless Configuration.auto_user_instrumentation_enabled?
            return @app.call(env) unless AppSec.active_context

            unless env.key?(WARDEN_KEY)
              Datadog.logger.debug { 'AppSec: unable to track requests, due to missing warden manager' }
              return @app.call(env)
            end

            context = AppSec.active_context
            if context.trace.nil? || context.span.nil?
              Datadog.logger.debug { 'AppSec: unable to track requests, due to missing trace or span' }
              return @app.call(env)
            end

            id = transform(extract_id(env[WARDEN_KEY]))
            if id
              unless context.span.has_tag?(Ext::TAG_USR_ID)
                context.span[Ext::TAG_USR_ID] = id
                AppSec::Instrumentation.gateway.push(
                  'identity.set_user', AppSec::Instrumentation::Gateway::User.new(id, nil)
                )
              end

              context.span[Ext::TAG_DD_USR_ID] = id.to_s
              context.span[Ext::TAG_DD_COLLECTION_MODE] ||= Configuration.auto_user_instrumentation_mode
            end

            @app.call(env)
          end

          private

          def extract_id(warden)
            session_serializer = warden.session_serializer

            key = session_key_for(session_serializer, ::Devise.default_scope)
            id = session_serializer.session[key]&.dig(0, 0)

            return id if ::Devise.mappings.size == 1
            return "#{::Devise.default_scope}:#{id}" if id

            ::Devise.mappings.each_key do |scope|
              next if scope == ::Devise.default_scope

              key = session_key_for(session_serializer, scope)
              id = session_serializer.session[key]&.dig(0, 0)

              return "#{scope}:#{id}" if id
            end

            nil
          end

          def session_key_for(session_serializer, scope)
            @devise_session_scope_keys[scope] ||= session_serializer.key_for(scope)
          end

          def transform(value)
            return if value.nil?
            return value.to_s unless anonymize?

            Anonymizer.anonimyze(value.to_s)
          end

          def anonymize?
            Configuration.auto_user_instrumentation_mode ==
              AppSec::Configuration::Settings::ANONYMIZATION_AUTO_USER_INSTRUMENTATION_MODE
          end
        end
      end
    end
  end
end
