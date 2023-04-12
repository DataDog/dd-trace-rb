module Datadog
  module Tracing
    module Contrib
      module Kafka
        # Kafka integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_KAFKA_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_KAFKA_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_KAFKA_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_CONNECTION_REQUEST = 'kafka.connection.request'.freeze
          SPAN_CONSUMER_HEARTBEAT = 'kafka.consumer.heartbeat'.freeze
          SPAN_CONSUMER_JOIN_GROUP = 'kafka.consumer.join_group'.freeze
          SPAN_CONSUMER_LEAVE_GROUP = 'kafka.consumer.leave_group'.freeze
          SPAN_CONSUMER_SYNC_GROUP = 'kafka.consumer.sync_group'.freeze
          SPAN_DELIVER_MESSAGES = 'kafka.producer.deliver_messages'.freeze
          SPAN_PROCESS_BATCH = 'kafka.consumer.process_batch'.freeze
          SPAN_PROCESS_MESSAGE = 'kafka.consumer.process_message'.freeze
          SPAN_SEND_MESSAGES = 'kafka.producer.send_messages'.freeze
          TAG_ATTEMPTS = 'kafka.attempts'.freeze
          TAG_API = 'kafka.api'.freeze
          TAG_CLIENT = 'kafka.client'.freeze
          TAG_GROUP = 'kafka.group'.freeze
          TAG_HIGHWATER_MARK_OFFSET = 'kafka.highwater_mark_offset'.freeze
          TAG_MESSAGE_COUNT = 'kafka.message_count'.freeze
          TAG_MESSAGE_KEY = 'kafka.message_key'.freeze
          TAG_DELIVERED_MESSAGE_COUNT = 'kafka.delivered_message_count'.freeze
          TAG_OFFSET = 'kafka.offset'.freeze
          TAG_OFFSET_LAG = 'kafka.offset_lag'.freeze
          TAG_PARTITION = 'kafka.partition'.freeze
          TAG_REQUEST_SIZE = 'kafka.request_size'.freeze
          TAG_RESPONSE_SIZE = 'kafka.response_size'.freeze
          TAG_SENT_MESSAGE_COUNT = 'kafka.sent_message_count'.freeze
          TAG_TOPIC = 'kafka.topic'.freeze
          TAG_TOPIC_PARTITIONS = 'kafka.topic_partitions'.freeze
          TAG_COMPONENT = 'kafka'.freeze
          TAG_OPERATION_CONNECTION_REQUEST = 'connection.request'.freeze
          TAG_OPERATION_CONSUMER_HEARTBEAT = 'consumer.heartbeat'.freeze
          TAG_OPERATION_CONSUMER_JOIN_GROUP = 'consumer.join_group'.freeze
          TAG_OPERATION_CONSUMER_LEAVE_GROUP = 'consumer.leave_group'.freeze
          TAG_OPERATION_CONSUMER_SYNC_GROUP = 'consumer.sync_group'.freeze
          TAG_OPERATION_DELIVER_MESSAGES = 'producer.deliver_messages'.freeze
          TAG_OPERATION_PROCESS_BATCH = 'consumer.process_batch'.freeze
          TAG_OPERATION_PROCESS_MESSAGE = 'consumer.process_message'.freeze
          TAG_OPERATION_SEND_MESSAGES = 'producer.send_messages'.freeze
          TAG_MESSAGING_SYSTEM = 'kafka'.freeze
        end
      end
    end
  end
end
