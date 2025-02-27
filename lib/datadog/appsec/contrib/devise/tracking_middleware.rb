# frozen_string_literal: true

require_relative '../../anonymizer'

module Datadog
  module AppSec
    module Contrib
      module Devise
        # A Rack middleware capable tracking currently signed user
        class TrackingMiddleware
          def initialize(app)
            @app = app
          end

          def call(env)
            return @app.call(env) unless AppSec.enabled?
            return @app.call(env) unless Configuration.auto_user_instrumentation_enabled?
            return @app.call(env) unless AppSec.active_context

            # TODO: Add check for trace and span
            unless env.key?('warden')
              # TODO: puts debugging message
              return @app.call(env)
            end

            context = AppSec.active_context
            id = transform(extract_id(env['warden']))

            if id
              context.span['usr.id'] ||= id.to_s
              context.span['_dd.appsec.usr.id'] = id.to_s
              context.span['_dd.appsec.user.collection_mode'] ||= Configuration.auto_user_instrumentation_mode
            end

            @app.call(env)
          end

          private

          def extract_id(warden)
            session_serializer = warden.session_serializer

            key = session_serializer.key_for(::Devise.default_scope)
            id = session_serializer.session[key]&.dig(0, 0)

            return id if ::Devise.mappings.size == 1
            return "#{::Devise.default_scope}:#{id}" if id

            ::Devise.mappings.each_key do |scope|
              next if scope == ::Devise.default_scope

              key = session_serializer.key_for(scope)
              id = session_serializer.session[key]&.dig(0, 0)

              return "#{scope}:#{id}" unless id.nil?
            end

            nil
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
