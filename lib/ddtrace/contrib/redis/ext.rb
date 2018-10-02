module Datadog
  module Contrib
    module Redis
      # Redis integration constants
      module Ext
        APP = 'redis'.freeze
        SERVICE_NAME = 'redis'.freeze
        TYPE = 'redis'.freeze

        METRIC_PIPELINE_LEN = 'redis.pipeline_length'.freeze

        SPAN_COMMAND = 'redis.command'.freeze

        TAG_DB = 'out.redis_db'.freeze
        TAG_RAW_COMMAND = 'redis.raw_command'.freeze
      end
    end
  end
end
