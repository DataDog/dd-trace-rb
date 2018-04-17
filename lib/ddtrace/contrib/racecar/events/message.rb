require 'ddtrace/contrib/racecar/event'

module Datadog
  module Contrib
    module Racecar
      module Events
        # Defines instrumentation for process_message.racecar event
        module Message
          include Racecar::Event

          EVENT_NAME = 'process_message.racecar'.freeze
          SPAN_NAME = 'racecar.message'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            self::SPAN_NAME
          end
        end
      end
    end
  end
end
