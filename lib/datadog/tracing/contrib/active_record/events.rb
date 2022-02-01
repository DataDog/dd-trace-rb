# typed: false
require 'datadog/tracing/contrib/active_record/events/instantiation'
require 'datadog/tracing/contrib/active_record/events/sql'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # Defines collection of instrumented ActiveRecord events
        module Events
          ALL = [
            Events::Instantiation,
            Events::SQL
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
