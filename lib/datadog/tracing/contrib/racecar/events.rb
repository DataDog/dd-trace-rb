# typed: false
require 'datadog/tracing/contrib/racecar/events/batch'
require 'datadog/tracing/contrib/racecar/events/message'
require 'datadog/tracing/contrib/racecar/events/consume'

module Datadog
  module Tracing
    module Contrib
      module Racecar
        # Defines collection of instrumented Racecar events
        module Events
          ALL = [
            Events::Consume,
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
end
