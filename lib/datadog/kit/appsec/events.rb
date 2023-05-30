# frozen_string_literal: true

require_relative '../identity'

module Datadog
  module Kit
    module AppSec
      # Tracking events
      module Events
        module_function

        LOGIN_SUCCESS_EVENT = 'users.login.success'
        LOGIN_FAILURE_EVENT = 'users.login.failure'
        SIGNUP_EVENT = 'users.signup'

        # Attach login success event information to the trace
        #
        # This method is experimental and may change in the future.
        #
        # @param trace [TraceOperation] Trace to attach data to. Defaults to
        #   active trace.
        # @param span [SpanOperation] Span to attach data to. Defaults to
        #   active span on trace. Note that this should be a service entry span.
        #   When AppSec is enabled, the expected span and trace are automatically
        #   used as defaults.
        # @param user [Hash<Symbol, String>] User information to pass to
        #   Datadog::Kit::Identity.set_user. Must contain at least :id as key.
        # @param others [Hash<String || Symbol, String>] Additional free-form
        #   event information to attach to the trace.
        def self.track_login_success(trace = nil, span = nil, user:, **others)
          if (appsec_scope = Datadog::AppSec.active_scope)
            trace = appsec_scope.trace
            span = appsec_scope.service_entry_span
          end

          trace ||= Datadog::Tracing.active_trace
          span ||= trace.active_span || Datadog::Tracing.active_span

          raise ArgumentError, "span #{span.span_id} does not belong to trace #{trace.id}" if trace.id != span.trace_id

          track(LOGIN_SUCCESS_EVENT, trace, span, **others)

          user_options = user.dup
          user_id = user_options.delete(:id)

          raise ArgumentError, 'missing required key: :user => { :id }' if user_id.nil?

          Kit::Identity.set_user(trace, span, id: user_id, **user_options)
        end

        # Attach login failure event information to the trace
        #
        # This method is experimental and may change in the future.
        #
        # @param trace [TraceOperation] Trace to attach data to. Defaults to
        #   active trace.
        # @param span [SpanOperation] Span to attach data to. Defaults to
        #   active span on trace. Note that this should be a service entry span.
        #   When AppSec is enabled, the expected span and trace are automatically
        #   used as defaults.
        # @param user_id [String] User id that attempted login
        # @param user_exists [bool] Whether the user id that did a login attempt exists.
        # @param others [Hash<String || Symbol, String>] Additional free-form
        #   event information to attach to the trace.
        def self.track_login_failure(trace = nil, span = nil, user_id:, user_exists:, **others)
          if (appsec_scope = Datadog::AppSec.active_scope)
            trace = appsec_scope.trace
            span = appsec_scope.service_entry_span
          end

          trace ||= Datadog::Tracing.active_trace
          span ||= trace.active_span || Datadog::Tracing.active_span

          raise ArgumentError, "span #{span.span_id} does not belong to trace #{trace.id}" if trace.id != span.trace_id

          track(LOGIN_FAILURE_EVENT, trace, span, **others)

          raise ArgumentError, 'user_id cannot be nil' if user_id.nil?

          span.set_tag('appsec.events.users.login.failure.usr.id', user_id)
          span.set_tag('appsec.events.users.login.failure.usr.exists', user_exists)
        end

        # Attach signup event information to the trace
        #
        # This method is experimental and may change in the future.
        #
        # @param trace [TraceOperation] Trace to attach data to.
        # @param user [Hash<Symbol, String>] User information to pass to
        #   Datadog::Kit::Identity.set_user. Must contain at least :id as key.
        # @param others [Hash<String || Symbol, String>] Additional free-form
        #   event information to attach to the trace.
        def track_signup(trace, user:, **others, &custom_track_tags_block)
          user_options = user.dup
          user_id = user_options.delete(:id)

          raise ArgumentError, 'missing required key: :user => { :id }' if user_id.nil?

          track(SIGNUP_EVENT, trace, **others, &custom_track_tags_block)
          Kit::Identity.set_user(trace, id: user_id, **user_options)
        end

        # Attach custom event information to the trace
        #
        # This method is experimental and may change in the future.
        #
        # @param event [String] Mandatory. Event code.
        # @param trace [TraceOperation] Trace to attach data to. Defaults to
        #   active trace.
        # @param span [SpanOperation] Span to attach data to. Defaults to
        #   active span on trace. Note that this should be a service entry span.
        #   When AppSec is enabled, the expected span and trace are automatically
        #   used as defaults.
        # @param others [Hash<Symbol, String>] Additional free-form
        #   event information to attach to the trace. Key must not
        #   be :track.
        def self.track(event, trace = nil, span = nil, **others)
          if (appsec_scope = Datadog::AppSec.active_scope)
            trace = appsec_scope.trace
            span = appsec_scope.service_entry_span
          end

          trace ||= Datadog::Tracing.active_trace
          span ||= trace.active_span || Datadog::Tracing.active_span

          raise ArgumentError, "span #{span.span_id} does not belong to trace #{trace.id}" if trace.id != span.trace_id

          span.set_tag("appsec.events.#{event}.track", 'true')

          trace.set_tag("appsec.events.#{event}.track", 'true')
          custom_track_tags_block.call(trace, event)
          others.each do |k, v|
            raise ArgumentError, 'key cannot be :track' if k.to_sym == :track

            span.set_tag("appsec.events.#{event}.#{k}", v) unless v.nil?
          end

          trace.keep!
        end
      end
    end
  end
end
