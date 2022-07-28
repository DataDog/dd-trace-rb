# typed: false

require_relative '../ext'
require_relative '../event'

module Datadog
  module Tracing
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

            def span_options
              super.merge(tags: { Tracing::Metadata::Ext::TAG_OPERATION => Ext::TAG_OPERATION_BATCH })
            end
          end
        end
      end
    end
  end
end
