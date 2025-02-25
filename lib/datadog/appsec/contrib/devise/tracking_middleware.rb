# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Devise
        # TODO
        class TrackingMiddleware
          def initialize(app)
            @app = app
          end

          # TODO
          def call(env)
            return @app.call(env) unless AppSec.enabled?
            return @app.call(env) unless Configuration.auto_user_instrumentation_enabled?
            return @app.call(env) unless AppSec.active_context

            unless env.key?('warden')
              # TODO: puts debugging message
              return @app.call(env)
            end

            context = AppSec.active_context
            session_serializer = env['warden'].session_serializer

            key = session_serializer.key_for(::Devise.default_scope)
            id = session_serializer.session[key]&.dig(0, 0)

            if id.nil?
              ::Devise.mappings.each_key do |scope|
                next if scope == ::Devise.default_scope

                key = session_serializer.key_for(scope)
                id = session_serializer.session[key]&.dig(0, 0)
                break unless id.nil?
              end
            end

            if id
              context.span.set_tag('usr.id', id.to_s) unless context.span.has_tag?('usr.id')
              context.span.set_tag('_dd.appsec.usr.id', id.to_s)
              unless context.span.has_tag?('_dd.appsec.user.collection_mode')
                context.span.set_tag('_dd.appsec.user.collection_mode', Configuration.auto_user_instrumentation_mode)
              end
            end

            @app.call(env)
          end
        end
      end
    end
  end
end
