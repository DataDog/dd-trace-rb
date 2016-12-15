require 'rails/all'
require 'rails/test_help'

module RailsTrace
  class TestApplication < Rails::Application
    # common settings between all Rails versions
    def initialize(*args)
      super(*args)
      redis_host = ENV['DATADOG_TEST_REDIS_CACHE_HOST']
      redis_port = ENV['DATADOG_TEST_REDIS_CACHE_PORT']
      if redis_host && redis_port
        puts "using redis cache on #{redis_host}:#{redis_port}"
        config.cache_store = :redis_store, { host: redis_host, port: redis_port }
      else
        config.cache_store = :file_store, '/tmp/ddtrace-rb/cache/'
      end
      config.eager_load = false
      config.secret_key_base = 'not_so_secret'
    end

    # configure the application: it loads common controllers,
    # initializes the application and runs all migrations;
    # the require order is important
    def test_config
      require 'contrib/rails/apps/controllers'
      initialize!
      require 'contrib/rails/apps/models'
    end
  end
end
