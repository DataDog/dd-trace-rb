require 'ddtrace/contrib/action_cable/event'
require 'ddtrace/contrib/action_cable/events/broadcast'
require 'ddtrace/contrib/action_cable/events/perform_action'
require 'ddtrace/contrib/action_cable/events/transmit'

module Datadog
  module Contrib
    module ActionCable
      # Defines collection of instrumented ActionCable events
      module Events
        ALL = [
          Events::Broadcast,
          Events::PerformAction,
          Events::Transmit
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
