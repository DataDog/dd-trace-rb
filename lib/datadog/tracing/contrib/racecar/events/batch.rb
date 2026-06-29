# frozen_string_literal: true

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

            EVENT_NAME = 'process_batch.racecar'

            module_function

            def event_name
              self::EVENT_NAME
            end

            def span_name
              Ext::SPAN_BATCH
            end

            def span_options
              super.merge(
                tags: {Tracing::Metadata::Ext::TAG_OPERATION => Ext::TAG_OPERATION_BATCH,
                       Tracing::Metadata::Ext::TAG_KIND => Tracing::Metadata::Ext::SpanKind::TAG_CONSUMER}
              )
            end

            # The batch event payload carries no per-message headers, so the
            # best we can do is a topic-level checkpoint, mirroring the Kafka
            # integration's `each_batch` behavior.
            def consume_checkpoint(payload)
              Datadog::DataStreams.set_consume_checkpoint(
                type: Ext::TAG_MESSAGING_SYSTEM,
                source: payload[:topic],
                auto_instrumentation: true,
              )

              track_consumer_lag(payload[:topic], payload[:partition], payload[:last_offset])
            end
          end
        end
      end
    end
  end
end
