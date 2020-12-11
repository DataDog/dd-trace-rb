require 'ddtrace/contrib/kafka/ext'
require 'ddtrace/contrib/kafka/event'
require 'ddtrace/contrib/kafka/consumer_event'

module Datadog
  module Contrib
    module Kafka
      module Events
        module Consumer
          # Defines instrumentation for process_batch.consumer.kafka event
          module ProcessBatch
            include Kafka::Event
            extend Kafka::ConsumerEvent

            EVENT_NAME = 'process_batch.consumer.kafka'.freeze

            def self.process(span, _event, _id, payload)
              super

              span.resource = payload[:topic]

              span.set_tag(Ext::TAG_TOPIC, payload[:topic]) if payload.key?(:topic)
              span.set_tag(Ext::TAG_MESSAGE_COUNT, payload[:message_count]) if payload.key?(:message_count)
              span.set_tag(Ext::TAG_PARTITION, payload[:partition]) if payload.key?(:partition)
              if payload.key?(:highwater_mark_offset)
                span.set_tag(Ext::TAG_HIGHWATER_MARK_OFFSET, payload[:highwater_mark_offset])
              end
              span.set_tag(Ext::TAG_OFFSET_LAG, payload[:offset_lag]) if payload.key?(:offset_lag)
            end

            module_function

            def span_name
              Ext::SPAN_PROCESS_BATCH
            end
          end
        end
      end
    end
  end
end
