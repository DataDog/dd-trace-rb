module Datadog
  module Ext
    module Redis
      # type of the spans
      TYPE = 'redis'.freeze

      # net extension
      DB = 'out.redis_db'.freeze

      # raw command
      RAW_COMMAND = 'redis.raw_command'.freeze

      # pipeline length
      PIPELINE_LEN = 'redis.pipeline_length'.freeze
    end
  end
end
