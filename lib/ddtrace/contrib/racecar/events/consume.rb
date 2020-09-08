require 'ddtrace/contrib/racecar/ext'
require 'ddtrace/contrib/racecar/event'

module Datadog
  module Contrib
    module Racecar
      module Events
        # Defines instrumentation for main_loop.racecar event
        module Consume
          include Racecar::Event

          EVENT_NAME = 'main_loop.racecar'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_CONSUME
          end
        end
      end
    end
  end
end
