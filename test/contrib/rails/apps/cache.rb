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

  return :redis_store, { url: ENV['REDIS_URL'] } if ENV['REDIS_URL']
  [:file_store, '/tmp/ddtrace-rb/cache/']
end
