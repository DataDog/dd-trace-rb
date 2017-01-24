module Datadog
  module Ext
    module Redis
      # type of the spans
      TYPE = 'redis'.freeze

      # net extension
      DB = 'out.redis_db'.freeze

      # standard tags
      RAWCMD = 'redis.raw_command'.freeze
    end
  end
end
