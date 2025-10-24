# frozen_string_literal: true

require_relative 'events/render'

module Datadog
  module Tracing
    module Contrib
      module ViewComponent
        # Defines collection of instrumented ViewComponent events
        module Events
          ALL = [
            Events::Render
          ].freeze

          module_function

          def all
            self::ALL
          end

          def subscriptions
            all.collect(&:subscriptions).flat_map(&:to_a)
          end

          def subscribe!
            all.each(&:subscribe!)
          end
        end
      end
    end
  end
end
