module Datadog
  module Tracing
    module Contrib
      module Pubsub
        # PubSub integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_PUBSUB_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_PUBSUB_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_PUBSUB_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_SEND_MESSAGES = 'pubsub.producer.send_messages'.freeze
          SPAN_RECEIVE_MESSAGES = 'pubsub.consumer.receive_message'.freeze
          TAG_MESSAGING_SYSTEM = 'pubsub'.freeze
        end
      end
    end
  end
end
