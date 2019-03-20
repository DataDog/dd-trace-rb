module Datadog
  module Contrib
    module Redis
      # Redis integration constants
      module Ext
        APP = 'redis'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_REDIS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_REDIS_ANALYTICS_SAMPLE_RATE'.freeze
        METRIC_PIPELINE_LEN = 'redis.pipeline_length'.freeze
        SERVICE_NAME = 'redis'.freeze
        SPAN_COMMAND = 'redis.command'.freeze
        TAG_DB = 'out.redis_db'.freeze
        TAG_RAW_COMMAND = 'redis.raw_command'.freeze
        TYPE = 'redis'.freeze
      end
    end
  end
end
