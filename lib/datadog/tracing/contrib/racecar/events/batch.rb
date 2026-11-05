# frozen_string_literal: true

require_relative "../ext"
require_relative "../event"

module Datadog
  module Tracing
    module Contrib
      module Racecar
        module Events
          # Defines instrumentation for process_batch.racecar event
          module Batch
            include Racecar::Event

            EVENT_NAME = "process_batch.racecar"

            def self.event_name
              self::EVENT_NAME
            end

            def self.span_name
              Ext::SPAN_BATCH
            end

            def self.span_options
              super.merge(
                tags: {Tracing::Metadata::Ext::TAG_OPERATION => Ext::TAG_OPERATION_BATCH,
                       Tracing::Metadata::Ext::TAG_KIND => Tracing::Metadata::Ext::SpanKind::TAG_CONSUMER},
              )
            end
          end
        end
      end
    end
  end
end
