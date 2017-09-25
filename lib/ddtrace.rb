require 'ddtrace/monkey'
require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  @tracer = Datadog::Tracer.new()

  # Default tracer that can be used as soon as +ddtrace+ is required:
  #
  #   require 'ddtrace'
  #
  #   span = Datadog.tracer.trace('web.request')
  #   span.finish()
  #
  # If you want to override the default tracer, the recommended way
  # is to "pin" your own tracer onto your traced component:
  #
  #   tracer = Datadog::Tracer.new
  #   pin = Datadog::Pin.get_from(mypatchcomponent)
  #   pin.tracer = tracer

  def self.tracer
    @tracer
  end
end

# Datadog auto instrumentation for frameworks
if defined?(Rails::VERSION)
  if !ENV['DISABLE_DATADOG_RAILS']
    if Rails::VERSION::MAJOR.to_i >= 3
      require 'ddtrace/contrib/rails/framework'
      require 'ddtrace/contrib/rails/middlewares'

      module Datadog
        # Railtie class initializes
        class Railtie < Rails::Railtie
          config.app_middleware.use(Datadog::Contrib::Rails::ExceptionMiddleware)

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
      Datadog::Tracer.log.warn 'Detected a Rails version < 3.x.'\
                               'This version is not supported yet and the'\
                               'auto-instrumentation for core components will be disabled.'
    end
  else
    Datadog::Tracer.log.info 'Skipping Rails auto-instrumentation, DISABLE_DATADOG_RAILS is set.'
  end
end
