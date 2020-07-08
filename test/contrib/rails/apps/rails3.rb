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

# Initialize the Rails application
require 'contrib/rails/apps/routes'
require 'contrib/rails/apps/controllers'

def initialize_rails!
  Rails3.initialize!
  require 'contrib/rails/apps/models'

  # Rails < 4 doesn't keep good track internally if it's been
  # initialized or not, so we have to do it.
  Rails.instance_variable_set(:@dd_rails_initialized, true)
end

def rails_initialized?
  Rails.instance_variable_get(:@dd_rails_initialized)
end
