# typed: true
require 'ddtrace/contrib/kafka/ext'
require 'ddtrace/contrib/kafka/event'
require 'ddtrace/contrib/kafka/consumer_event'
require 'ddtrace/contrib/kafka/consumer_group_event'

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Events
          module ConsumerGroup
            # Defines instrumentation for leave_group.consumer.kafka event
            module LeaveGroup
              include Kafka::Event
              extend Kafka::ConsumerEvent
              extend Kafka::ConsumerGroupEvent

              EVENT_NAME = 'leave_group.consumer.kafka'.freeze

              module_function

              def span_name
                Ext::SPAN_CONSUMER_LEAVE_GROUP
              end

              def span_options
                super.merge({ tags: { Tracing::Metadata::Ext::TAG_OPERATION => Ext::TAG_OPERATION_CONSUMER_LEAVE_GROUP } })
              end
            end
          end
        end
      end
    end
  end
end
