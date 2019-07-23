module Datadog
  module Contrib
    module Kafka
      # Kafka integration constants
      module Ext
        APP = 'kafka'.freeze
        SERVICE_NAME = 'kafka'.freeze

        SPAN_REQUEST = 'kafka.request'.freeze

        TAG_CLUSTER = 'cluster'.freeze
        TAG_BUFFER_SIZE = 'buffer_size'.freeze
        TAG_PARTITION = 'partition'.freeze
      end
    end
  end
end
