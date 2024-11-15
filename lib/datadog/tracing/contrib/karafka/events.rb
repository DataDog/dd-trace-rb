# frozen_string_literal: true

require_relative 'events/worker/process'

module Datadog
  module Tracing
    module Contrib
      module Karafka
        # Defines collection of instrumented Kafka events
        module Events
          ALL = [
            Events::Worker::Process,
          ]

          module_function

          def all
            self::ALL
          end

          def subscribe!
            all.each(&:subscribe!)
          end
        end
      end
    end
  end
end
