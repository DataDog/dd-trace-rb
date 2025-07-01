# frozen_string_literal: true

require_relative '../../identity'

module Datadog
  module Kit
    module AppSec
      module Events
        # The second version of Business Logic Events SDK
        module V2
          LOGIN_SUCCESS_EVENT = 'users.login.success'
          LOGIN_FAILURE_EVENT = 'users.login.failure'
          TELEMETRY_METRICS_NAMESPACE = 'appsec'
          TELEMETRY_METRICS_SDK_EVENT = 'sdk.event'
          TELEMETRY_METRICS_SDK_VERSION = 'v2'
          TELEMETRY_METRICS_EVENTS_INTO_TYPES = {
            LOGIN_SUCCESS_EVENT => 'login_success',
            LOGIN_FAILURE_EVENT => 'login_failure'
          }.freeze

          class << self
            # TODO: Write doc
            def track_user_login_success(login, user_or_id = nil, **metadata)
              trace = service_entry_trace
              span = service_entry_span

              if trace.nil? || span.nil?
                return Datadog.logger.warn(
                  'Kit::AppSec: Tracing is not enabled. Please enable tracing if you want to track events'
                )
              end

              user_attributes = build_user_attributes(user_or_id, login)

              export_tags(span, metadata, namespace: LOGIN_SUCCESS_EVENT)
              export_tags(span, user_attributes, namespace: "#{LOGIN_SUCCESS_EVENT}.usr")
              span.set_tag('appsec.events.users.login.success.track', 'true')
              span.set_tag('_dd.appsec.events.users.login.success.sdk', 'true')

              trace.keep!

              record_event_telemetry_metric(LOGIN_SUCCESS_EVENT)
              ::Datadog::AppSec::Instrumentation.gateway.push('appsec.events.user_lifecycle', LOGIN_SUCCESS_EVENT)

              return Kit::Identity.set_user(trace, span, **user_attributes) if user_attributes.key?(:id)

              # NOTE: This is a fallback for the case when we don't have an ID,
              #       but need to trigger WAF.
              user = ::Datadog::AppSec::Instrumentation::Gateway::User.new(nil, login)
              ::Datadog::AppSec::Instrumentation.gateway.push('identity.set_user', user)
            end

            def track_user_login_failure(login, user_exists = false, **metadata)
              trace = service_entry_trace
              span = service_entry_span

              if trace.nil? || span.nil?
                return Datadog.logger.warn(
                  'Kit::AppSec: Tracing is not enabled. Please enable tracing if you want to track events'
                )
              end

              unless user_exists.is_a?(TrueClass) || user_exists.is_a?(FalseClass)
                raise TypeError, 'user existence flag must be a boolean'
              end

              export_tags(span, metadata, namespace: LOGIN_FAILURE_EVENT)
              span.set_tag('appsec.events.users.login.failure.track', 'true')
              span.set_tag('_dd.appsec.events.users.login.failure.sdk', 'true')
              span.set_tag('appsec.events.users.login.failure.usr.login', login)
              span.set_tag('appsec.events.users.login.failure.usr.exists', user_exists.to_s)

              trace.keep!

              record_event_telemetry_metric(LOGIN_FAILURE_EVENT)
              ::Datadog::AppSec::Instrumentation.gateway.push('appsec.events.user_lifecycle', LOGIN_FAILURE_EVENT)

              user = ::Datadog::AppSec::Instrumentation::Gateway::User.new(nil, login)
              ::Datadog::AppSec::Instrumentation.gateway.push('identity.set_user', user)
            end

            private

            # NOTE: Current tracer implementation does not provide a way to
            #       get the service entry span. This is a shortcut we take now.
            def service_entry_trace
              return Datadog::Tracing.active_trace unless Datadog::AppSec.active_context

              Datadog::AppSec.active_context&.trace
            end

            # NOTE: Current tracer implementation does not provide a way to
            #       get the service entry span. This is a shortcut we take now.
            def service_entry_span
              return Datadog::Tracing.active_span unless Datadog::AppSec.active_context

              Datadog::AppSec.active_context&.span
            end

            def build_user_attributes(user_or_id, login)
              raise TypeError, 'login argument must be a String' unless login.is_a?(String)

              return { login: login } unless user_or_id
              return { login: login, id: user_or_id } unless user_or_id.is_a?(Hash)

              raise ArgumentError, 'missing required key `:id`' unless user_or_id.key?(:id)
              raise TypeError, 'key `:id` must be a String' unless user_or_id[:id].is_a?(String)

              user_or_id.merge(login: login)
            end

            def export_tags(span, source, namespace:)
              namespace = "appsec.events.#{namespace}"
              source.each do |key, value|
                next if value.nil?

                span.set_tag("#{namespace}.#{key}", value)
              end
            end

            # TODO: In case if we need to introduce telemetry metrics to the SDK v1
            #       or highly increase the number of metrics, this method should be
            #       extracted into a proper module.
            def record_event_telemetry_metric(event)
              telemetry = ::Datadog.send(:components)&.telemetry

              if telemetry.nil?
                return Datadog.logger.debug(
                  'Kit::AppSec: Telemetry component is unavailabl. Skip recording SDK metrics'
                )
              end

              tags = {
                event_type: TELEMETRY_METRICS_EVENTS_INTO_TYPES[event],
                sdk_version: TELEMETRY_METRICS_SDK_VERSION
              }
              telemetry.inc(TELEMETRY_METRICS_NAMESPACE, TELEMETRY_METRICS_SDK_EVENT, 1, tags: tags)
            end
          end
        end
      end
    end
  end
end
