# frozen_string_literal: true

require_relative "events/batch"
require_relative "events/message"
require_relative "events/consume"

module Datadog
  module Tracing
    module Contrib
      module Racecar
        # Defines collection of instrumented Racecar events
        module Events
          ALL = [
            Events::Consume,
            Events::Batch,
            Events::Message,
          ].freeze

          def self.all
            self::ALL
          end

          def self.subscriptions
            all.collect(&:subscriptions).collect(&:to_a).flatten
          end

          def self.subscribe!
            all.each(&:subscribe!)
          end
        end
      end
    end
  end
end
