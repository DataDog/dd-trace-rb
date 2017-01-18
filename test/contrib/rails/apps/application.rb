require 'rails/all'
require 'rails/test_help'
require 'contrib/rails/apps/cache'

module RailsTrace
  class TestApplication < Rails::Application
    # common settings between all Rails versions
    def initialize(*args)
      super(*args)
      config.cache_store = get_cache
      config.eager_load = false
      config.secret_key_base = 'not_so_secret'
    end

    # configure the application: it loads common controllers,
    # initializes the application and runs all migrations;
    # the require order is important
    def test_config
      # Enables the auto-instrumentation
      Rails.configuration.datadog_trace = {
        enabled: true,
        auto_instrument: true,
        auto_instrument_redis: true
      }
      require 'ddtrace'

      # Initialize the Rails application
      require 'contrib/rails/apps/controllers'
      initialize!
      require 'contrib/rails/apps/models'
    end
  end
end
