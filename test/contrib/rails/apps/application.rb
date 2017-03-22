require 'rails/all'
require 'rails/test_help'

require 'ddtrace'

module RailsTrace
  class TestApplication < Rails::Application
    # common settings between all Rails versions
    def initialize(*args)
      super(*args)
      redis_cache = [:redis_store, { url: ENV['REDIS_URL'] }]
      file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']
      config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
      config.active_job.queue_adapter = :sidekiq if ENV['USE_SIDEKIQ']
      config.eager_load = false
      config.secret_key_base = 'not_so_secret'
    end

    # configure the application: it loads common controllers,
    # initializes the application and runs all migrations;
    # the require order is important
    def test_config
      # Enables the auto-instrumentation for the testing application
      Rails.configuration.datadog_trace = {
        auto_instrument: true,
        auto_instrument_redis: true
      }

      # Initialize the Rails application
      require 'contrib/rails/apps/controllers'
      initialize!
      require 'contrib/rails/apps/models'
    end
  end
end
