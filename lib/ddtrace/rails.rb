require 'ddtrace'

if Rails::VERSION::MAJOR.to_i >= 3
  require 'ddtrace/contrib/rails/framework'

  module Datadog
    # Railtie class initializes
    class Railtie < Rails::Railtie
      # auto instrument Rails and third party components after
      # the framework initialization
      options = {}
      config.after_initialize do |app|
        Datadog::Contrib::Rails::Framework.configure(config: app.config)
        Datadog::Contrib::Rails::Framework.auto_instrument()
        Datadog::Contrib::Rails::Framework.auto_instrument_redis()
        Datadog::Contrib::Rails::Framework.auto_instrument_grape()

        # override Rack Middleware configurations with Rails
        options.update(::Rails.configuration.datadog_trace)
      end

      # Configure datadog settings before building the middleware stack.
      # This is required because the middleware stack is frozen after
      # the initialization and so it's too late to add our tracing
      # functionalities.
      initializer :datadog_config, before: :build_middleware_stack do |app|
        app.config.middleware.insert_before(
          0, Datadog::Contrib::Rack::TraceMiddleware, options
        )
      end
    end
  end
else
  logger = Logger.new(STDOUT)
  logger.warn 'Detected a Rails version < 3.x.'\
      'This version is not supported yet and the'\
      'auto-instrumentation for core components will be disabled.'
end
