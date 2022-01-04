# typed: false
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

          def span_options
            super.merge(tags: { Datadog::Ext::Metadata::TAG_OPERATION => Ext::TAG_OPERATION_CONSUME })
          end
        end
      end
    end
  end
end
