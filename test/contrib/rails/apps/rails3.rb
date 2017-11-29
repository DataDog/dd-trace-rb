require 'rails/all'
require 'rails/test_help'

require 'ddtrace'

class Rails3 < Rails::Application
  redis_cache = [:redis_store, { url: ENV['REDIS_URL'] }]
  file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']

  config.secret_token = 'f624861242e4ccf20eacb6bb48a886da'
  config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
  config.active_support.test_order = :random
  config.active_support.deprecation = :stderr
  config.consider_all_requests_local = true
  config.middleware.delete ActionDispatch::DebugExceptions if Rails.version >= '3.2.22.5'
end

# Enables the auto-instrumentation for the testing application
Datadog.configure do |c|
  c.use :rails
  c.use :redis
end

# Initialize the Rails application
require 'contrib/rails/apps/controllers'
Rails3.initialize!
require 'contrib/rails/apps/models'
