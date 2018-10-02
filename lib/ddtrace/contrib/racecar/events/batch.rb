require 'ddtrace/contrib/racecar/ext'
require 'ddtrace/contrib/racecar/event'

module Datadog
  module Contrib
    module Racecar
      module Events
        # Defines instrumentation for process_batch.racecar event
        module Batch
          include Racecar::Event

          EVENT_NAME = 'process_batch.racecar'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_BATCH
          end
        end
      end
    end
  end
end
