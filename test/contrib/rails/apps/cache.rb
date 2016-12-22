module RedisStoreDataAccessor
  attr_accessor :data
end

def get_cache
  # Rails3 does not define data as an accessor, we need it for our tests
  if defined?(::ActiveSupport::Cache::RedisStore)
    unless ::ActiveSupport::Cache::RedisStore.method_defined?(:data)
      ::ActiveSupport::Cache::RedisStore.prepend RedisStoreDataAccessor
    end
  end

  cache = nil
  redis_host = ENV['DATADOG_TEST_REDIS_CACHE_HOST']
  redis_port = ENV['DATADOG_TEST_REDIS_CACHE_PORT']
  if redis_host && redis_port
    puts "using redis cache on #{redis_host}:#{redis_port}"
    cache = :redis_store, { host: redis_host, port: redis_port }
  else
    cache = :file_store, '/tmp/ddtrace-rb/cache/'
  end
  cache
end
