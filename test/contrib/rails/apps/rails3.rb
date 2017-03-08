require 'rails/all'
require 'rails/test_help'

require 'ddtrace'

class Rails3 < Rails::Application
  redis_cache = [:redis_store, { url: ENV['REDIS_URL'] }]
  file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']
  config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
  config.secret_key_base = 'not_so_secret'
  config.active_support.test_order = :random
  config.active_support.deprecation = :stderr
end

# Enables the auto-instrumentation for the testing application
Rails.configuration.datadog_trace = {
  auto_instrument: true,
  auto_instrument_redis: true
}

# Initialize the Rails application
require 'contrib/rails/apps/controllers'
Rails3.initialize!
require 'contrib/rails/apps/models'
