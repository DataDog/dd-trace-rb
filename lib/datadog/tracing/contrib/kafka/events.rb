# typed: false
require 'datadog/tracing/contrib/kafka/events/connection/request'
require 'datadog/tracing/contrib/kafka/events/consumer/process_batch'
require 'datadog/tracing/contrib/kafka/events/consumer/process_message'
require 'datadog/tracing/contrib/kafka/events/consumer_group/heartbeat'
require 'datadog/tracing/contrib/kafka/events/consumer_group/join_group'
require 'datadog/tracing/contrib/kafka/events/consumer_group/leave_group'
require 'datadog/tracing/contrib/kafka/events/consumer_group/sync_group'
require 'datadog/tracing/contrib/kafka/events/produce_operation/send_messages'
require 'datadog/tracing/contrib/kafka/events/producer/deliver_messages'

module Datadog
  module Tracing
    module Contrib
      module Kafka
        # Defines collection of instrumented Kafka events
        module Events
          ALL = [
            Events::Connection::Request,
            Events::Consumer::ProcessBatch,
            Events::Consumer::ProcessMessage,
            Events::ConsumerGroup::Heartbeat,
            Events::ConsumerGroup::JoinGroup,
            Events::ConsumerGroup::LeaveGroup,
            Events::ConsumerGroup::SyncGroup,
            Events::ProduceOperation::SendMessages,
            Events::Producer::DeliverMessages
          ].freeze

          module_function

          def all
            self::ALL
          end

          def subscriptions
            all.collect(&:subscriptions).collect(&:to_a).flatten
          end

          def subscribe!
            all.each(&:subscribe!)
          end
        end
      end
    end
  end
end
