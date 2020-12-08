module Datadog
  module Contrib
    module Redis
      # Redis integration constants
      module Ext
        APP = 'redis'.freeze
        ENV_ENABLED = 'DD_TRACE_REDIS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_REDIS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_REDIS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_REDIS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_REDIS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_COMMAND_ARGS = 'DD_REDIS_COMMAND_ARGS'.freeze
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
