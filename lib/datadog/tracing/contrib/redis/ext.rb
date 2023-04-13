module Datadog
  module Tracing
    module Contrib
      module Redis
        # Redis integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_REDIS_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_REDIS_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_REDIS_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_REDIS_ANALYTICS_SAMPLE_RATE'.freeze
          ENV_COMMAND_ARGS = 'DD_REDIS_COMMAND_ARGS'.freeze
          METRIC_PIPELINE_LEN = 'redis.pipeline_length'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'redis'.freeze
          SPAN_COMMAND = 'redis.command'.freeze
          TAG_DB = 'out.redis_db'.freeze
          TAG_RAW_COMMAND = 'redis.raw_command'.freeze
          TYPE = 'redis'.freeze
          TAG_COMPONENT = 'redis'.freeze
          TAG_OPERATION_COMMAND = 'command'.freeze
          TAG_SYSTEM = 'redis'.freeze
          TAG_DATABASE_INDEX = 'db.redis.database_index'.freeze
        end
      end
    end
  end
end
