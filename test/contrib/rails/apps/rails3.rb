require 'rails/all'
require 'rails/test_help'
require 'contrib/rails/apps/cache'

class Rails3 < Rails::Application
  config.cache_store = get_cache
  config.secret_key_base = 'not_so_secret'
  config.active_support.test_order = :random
  config.active_support.deprecation = :stderr
end

# Enables the auto-instrumentation
Rails.configuration.datadog_trace = {
  enabled: true,
  auto_instrument: true,
  auto_instrument_redis: true
}
require 'ddtrace'

# Initialize the Rails application
require 'contrib/rails/apps/controllers'
Rails3.initialize!
require 'contrib/rails/apps/models'
