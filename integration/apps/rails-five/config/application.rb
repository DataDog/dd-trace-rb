require_relative 'boot'
require 'datadog/tracing/runtime/metrics'

# require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"
require "action_cable/engine"
# require "sprockets/railtie"
# require "rails/test_unit/railtie"

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
    config.load_defaults 5.2

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.
    # config.middleware.use TraceMiddleware
    # config.middleware.use ShortCircuitMiddleware
    # config.middleware.use ErrorMiddleware
    config.middleware.use CacheMiddleware

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = true

    config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }
    config.action_controller.perform_caching = true
  end
end
