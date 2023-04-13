module Datadog
  module Tracing
    module Contrib
      module Racecar
        # Racecar integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_RACECAR_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_RACECAR_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_RACECAR_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'racecar'.freeze
          SPAN_CONSUME = 'racecar.consume'.freeze
          SPAN_BATCH = 'racecar.batch'.freeze
          SPAN_MESSAGE = 'racecar.message'.freeze
          TAG_CONSUMER = 'kafka.consumer'.freeze
          TAG_FIRST_OFFSET = 'kafka.first_offset'.freeze
          TAG_MESSAGE_COUNT = 'kafka.message_count'.freeze
          TAG_OFFSET = 'kafka.offset'.freeze
          TAG_PARTITION = 'kafka.partition'.freeze
          TAG_TOPIC = 'kafka.topic'.freeze
          TAG_COMPONENT = 'racecar'.freeze
          TAG_OPERATION_CONSUME = 'consume'.freeze
          TAG_OPERATION_BATCH = 'batch'.freeze
          TAG_OPERATION_MESSAGE = 'message'.freeze
          TAG_MESSAGING_SYSTEM = 'kafka'.freeze
        end
      end
    end
  end
end
