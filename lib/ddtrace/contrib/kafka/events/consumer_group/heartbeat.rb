require 'ddtrace/contrib/kafka/ext'
require 'ddtrace/contrib/kafka/event'
require 'ddtrace/contrib/kafka/consumer_event'
require 'ddtrace/contrib/kafka/consumer_group_event'

module Datadog
  module Contrib
    module Kafka
      module Events
        module ConsumerGroup
          # Defines instrumentation for heartbeat.consumer.kafka event
          module Heartbeat
            include Kafka::Event
            extend Kafka::ConsumerEvent
            extend Kafka::ConsumerGroupEvent

            EVENT_NAME = 'heartbeat.consumer.kafka'.freeze

            def self.process(span, _event, _id, payload)
              super

              if payload.key?(:topic_partitions)
                payload[:topic_partitions].each do |topic, partitions|
                  span.set_tag("#{Ext::TAG_TOPIC_PARTITIONS}.#{topic}", partitions)
                end
              end
            end

            module_function

            def span_name
              Ext::SPAN_CONSUMER_HEARTBEAT
            end
          end
        end
      end
    end
  end
end
