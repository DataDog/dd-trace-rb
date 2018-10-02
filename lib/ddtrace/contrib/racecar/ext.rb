module Datadog
  module Contrib
    module Racecar
      # Racecar integration constants
      module Ext
        APP = 'racecar'.freeze
        SERVICE_NAME = 'racecar'.freeze

        SPAN_BATCH = 'racecar.batch'.freeze
        SPAN_MESSAGE = 'racecar.message'.freeze

        TAG_CONSUMER = 'kafka.consumer'.freeze
        TAG_FIRST_OFFSET = 'kafka.first_offset'.freeze
        TAG_MESSAGE_COUNT = 'kafka.message_count'.freeze
        TAG_OFFSET = 'kafka.offset'.freeze
        TAG_PARTITION = 'kafka.partition'.freeze
        TAG_TOPIC = 'kafka.topic'.freeze
      end
    end
  end
end
