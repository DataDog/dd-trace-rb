require 'rails/all'
require 'rails/test_help'
require 'ddtrace'
if ENV['USE_SIDEKIQ']
  require 'sidekiq/testing'
  require 'ddtrace/contrib/sidekiq/tracer'
end

module RailsTrace
  class TestApplication < Rails::Application
    # common settings between all Rails versions
    def initialize(*args)
      super(*args)
      redis_cache = [:redis_store, { url: ENV['REDIS_URL'] }]
      file_cache = [:file_store, '/tmp/ddtrace-rb/cache/']

      config.secret_key_base = 'f624861242e4ccf20eacb6bb48a886da'
      config.cache_store = ENV['REDIS_URL'] ? redis_cache : file_cache
      config.eager_load = false
      config.consider_all_requests_local = true
      config.middleware.delete ActionDispatch::DebugExceptions

      if ENV['USE_SIDEKIQ']
        config.active_job.queue_adapter = :sidekiq
        # add Sidekiq middleware
        Sidekiq::Testing.server_middleware do |chain|
          chain.add(
            Datadog::Contrib::Sidekiq::Tracer
          )
        end
      end
    end

    def config.database_configuration
      parsed = super
      raise parsed.to_yaml # Replace this line to add custom connections to the hash from database.yml
    end

    # configure the application: it loads common controllers,
    # initializes the application and runs all migrations;
    # the require order is important
    def test_config
      # Enables the auto-instrumentation for the testing application
      Datadog.configure do |c|
        c.use :rails
        c.use :redis
      end
      Rails.application.config.active_job.queue_adapter = :sidekiq

      # Initialize the Rails application
      require 'contrib/rails/apps/controllers'
      initialize!
      require 'contrib/rails/apps/models'
    end
  end
end
