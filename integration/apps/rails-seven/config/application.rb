require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

class TraceMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    Datadog::Tracing.trace('web.request', service: 'acme', resource: env['REQUEST_PATH']) do |span, trace|
      Datadog::Runtime::Metrics.associate_trace(trace)
      @app.call(env)
    end
  end
end

class ShortCircuitMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    return [200, {}, []]
  end
end

class ErrorMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
    raise
  end
end

class CustomError < StandardError
  def message
    'Custom error message!'
  end
end

class CacheMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request_id = env['action_dispatch.request_id']

    # NOTE: Disabled for now, suspected to cause memory growth.
    # Fetch from cache
    # Rails.cache.fetch(request_id) { request_id }

    @app.call(env)
  end
end

module Acme
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # config.middleware.use TraceMiddleware
    # config.middleware.use ShortCircuitMiddleware
    # config.middleware.use ErrorMiddleware
    config.middleware.use CacheMiddleware

    config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
    config.action_controller.perform_caching = true

    config.exceptions_app = self.routes
  end
end
