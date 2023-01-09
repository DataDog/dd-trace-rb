# typed: false
# frozen_string_literal: true

require_relative 'identity'

module Datadog
  module Kit
    # Tracking events
    module Events
      # Attach login event information to the trace
      #
      # @param trace [TraceOperation] Trace to attach data to.
      # @param success [bool] Whether login operation was successful or not.
      # @param user [Hash<Symbol, String>] User information to pass to
      #   Datadog::Kit::Identity.set_user. Must contain at least :id as key.
      # @param others [Hash<String || Symbol, String>] Additional free-form
      #   event information to attach to the trace.
      def self.track_login(trace, success:, user:, **others)
        subtag = success ? 'success' : 'failure'
        event = "users.login.#{subtag}"

        track(event, trace, **others)

        user_options = user.dup
        user_id = user.delete(:id)

        raise ArgumentError, 'missing required key: :user => { :id }' if user_id.nil?

        if success
          Kit::Identity.set_user(trace, id: user_id, **user_options)
        else
          trace.set_tag("appsec.events.users.login.#{subtag}.usr.id", user_id)
        end
      end

      # Attach custom event information to the trace
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
