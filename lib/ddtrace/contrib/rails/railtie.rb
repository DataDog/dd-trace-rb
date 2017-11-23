require 'ddtrace/contrib/rails/framework'
require 'ddtrace/contrib/rails/middlewares'
require 'ddtrace/contrib/rack/middlewares'

module Datadog
  # Railtie class initializes
  class Railtie < Rails::Railtie
    config.app_middleware.insert_before(0, Datadog::Contrib::Rack::TraceMiddleware)
    config.app_middleware.use(Datadog::Contrib::Rails::ExceptionMiddleware)

    config.after_initialize do |app|
      Datadog::Contrib::Rails::Framework.configure(config: app.config)
      Datadog::Contrib::Rails::Framework.auto_instrument
      Datadog::Contrib::Rails::Framework.auto_instrument_redis
      Datadog::Contrib::Rails::Framework.auto_instrument_grape
    end
  end
end
