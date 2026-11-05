# frozen_string_literal: true

require_relative "events/instantiation"
require_relative "events/sql"

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # Defines collection of instrumented ActiveRecord events
        module Events
          ALL = [
            Events::Instantiation,
            Events::SQL,
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
