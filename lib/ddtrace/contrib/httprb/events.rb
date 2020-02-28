require 'ddtrace/contrib/httprb/events/start_request'
require 'ddtrace/contrib/htpprb/events/request'

module Datadog
  module Contrib
    module Httprb
      # Defines collection of instrumented Racecar events
      module Events
        ALL = [
          Events::StartRequest,
          Events::Request
        ].freeze

        module_function

        def all
          self::ALL
        end

        def subscriptions
          all.collect(&:subscriptions).collect(&:to_a).flatten
        end

        def subscribe!
          all.each(&:subscribe!)
        end
      end
    end
  end
end
