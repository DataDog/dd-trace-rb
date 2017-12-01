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
      Datadog::Contrib::Rails::ActionController.instrument
      Datadog::Contrib::Rails::ActionView.instrument
      Datadog::Contrib::Rails::ActiveRecord.instrument
      Datadog::Contrib::Rails::ActiveSupport.instrument
    end
  end
end
