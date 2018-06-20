require 'ddtrace/contrib/racecar/events/batch'
require 'ddtrace/contrib/racecar/events/message'

module Datadog
  module Contrib
    module Racecar
      # Defines collection of instrumented Racecar events
      module Events
        ALL = [
          Events::Batch,
          Events::Message
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
