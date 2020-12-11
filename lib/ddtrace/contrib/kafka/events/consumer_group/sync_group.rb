require 'ddtrace/contrib/kafka/ext'
require 'ddtrace/contrib/kafka/event'
require 'ddtrace/contrib/kafka/consumer_event'
require 'ddtrace/contrib/kafka/consumer_group_event'

module Datadog
  module Contrib
    module Kafka
      module Events
        module ConsumerGroup
          # Defines instrumentation for sync_group.consumer.kafka event
          module SyncGroup
            include Kafka::Event
            extend Kafka::ConsumerEvent
            extend Kafka::ConsumerGroupEvent

            EVENT_NAME = 'sync_group.consumer.kafka'.freeze

            module_function

            def span_name
              Ext::SPAN_CONSUMER_SYNC_GROUP
            end
          end
        end
      end
    end
  end
end
