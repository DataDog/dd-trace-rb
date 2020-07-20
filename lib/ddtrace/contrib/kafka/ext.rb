module Datadog
  module Contrib
    module Kafka
      # Kafka integration constants
      module Ext
        APP = 'kafka'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_KAFKA_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_KAFKA_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'kafka'.freeze
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
      end
    end
  end
end
