module Datadog
  module Ext
    module Redis
      # type of the spans
      TYPE = 'redis'.freeze

      # net extension
      DB = 'out.redis_db'.freeze

      # standard tags
      RAWCMD = 'redis.raw_command'.freeze
      ARGS_LEN = 'redis.args_length'.freeze
      PIPELINE_LEN = 'redis.pipeline_length'.freeze
    end
  end
end
