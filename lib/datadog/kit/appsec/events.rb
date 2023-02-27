# frozen_string_literal: true

require_relative '../identity'

module Datadog
  module Kit
    module AppSec
      # Tracking events
      module Events
        LOGIN_SUCCESS_EVENT = 'users.login.success'
        LOGIN_FAILURE_EVENT = 'users.login.failure'

        # Attach login success event information to the trace
        #
        # This method is experimental and may change in the future.
        #
        # @param trace [TraceOperation] Trace to attach data to.
        # @param user [Hash<Symbol, String>] User information to pass to
        #   Datadog::Kit::Identity.set_user. Must contain at least :id as key.
        # @param others [Hash<String || Symbol, String>] Additional free-form
        #   event information to attach to the trace.
        def self.track_login_success(trace, user:, **others)
          track(LOGIN_SUCCESS_EVENT, trace, **others)

          user_options = user.dup
          user_id = user.delete(:id)

          raise ArgumentError, 'missing required key: :user => { :id }' if user_id.nil?

          Kit::Identity.set_user(trace, id: user_id, **user_options)
        end

        # Attach login failure event information to the trace
        #
        # This method is experimental and may change in the future.
        #
        # @param trace [TraceOperation] Trace to attach data to.
        # @param user_id [String] User id that attempted login
        # @param user_exists [bool] Whether the user id that did a login attempt exists.
        # @param others [Hash<String || Symbol, String>] Additional free-form
        #   event information to attach to the trace.
        def self.track_login_failure(trace, user_id:, user_exists:, **others)
          track(LOGIN_FAILURE_EVENT, trace, **others)

          raise ArgumentError, 'user_id cannot be nil' if user_id.nil?

          trace.set_tag('appsec.events.users.login.failure.usr.id', user_id)
          trace.set_tag('appsec.events.users.login.failure.usr.exists', user_exists)
        end

        # Attach custom event information to the trace
        #
        # This method is experimental and may change in the future.
        #
        # @param event [String] Mandatory. Event code.
        # @param trace [TraceOperation] Trace to attach data to.
        # @param others [Hash<Symbol, String>] Additional free-form
        #   event information to attach to the trace. Key must not
        #   be :track.
        def self.track(event, trace, **others)
          trace.set_tag("appsec.events.#{event}.track", 'true')

          others.each do |k, v|
            raise ArgumentError, 'key cannot be :track' if k.to_sym == :track

            trace.set_tag("appsec.events.#{event}.#{k}", v) unless v.nil?
          end

          trace.keep!
        end
      end
    end
  end
end
