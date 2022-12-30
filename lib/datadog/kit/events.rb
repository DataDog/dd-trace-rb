# typed: false

module Datadog
  module Kit
    # Tracking events
    module Events
      def self.track_login(trace, id:, success:, **others)
        subtag = success ? 'success' : 'failure'
        event = "users.login.#{subtag}"

        track(event, trace, **others)

        if success
          trace.set_tag('usr.id', id)
        else
          trace.set_tag("appsec.events.users.login.#{subtag}.usr.id", id)
        end
      end

      def self.track(event, trace, **others)
        trace.set_tag("appsec.events.#{event}.track", true)

        others.each do |k, v|
          trace.set_tag("appsec.events.#{event}.#{k}", v) unless v.nil?
        end

        trace.keep!
      end
    end
  end
end
