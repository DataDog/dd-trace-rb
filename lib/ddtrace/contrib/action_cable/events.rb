require 'ddtrace/contrib/action_cable/events/perform_action'

module Datadog
  module Contrib
    module ActionCable
      # Defines collection of instrumented ActionCable events
      module Events
        ALL = [
          Events::PerformAction
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
