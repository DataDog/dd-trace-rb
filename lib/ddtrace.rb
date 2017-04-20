require 'ddtrace/monkey'
require 'ddtrace/pin'
require 'ddtrace/tracer'

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
  if Rails::VERSION::MAJOR.to_i >= 3
    require 'ddtrace/contrib/rails/framework'

    module Datadog
      # Railtie class initializes
      class Railtie < Rails::Railtie
        # auto instrument Rails and third party components after
        # the framework initialization
        config.after_initialize do
          Datadog::Contrib::Rails::Framework.auto_instrument()
          Datadog::Contrib::Rails::Framework.auto_instrument_redis()
        end

        # Configure datadog settings before building the middleware stack.
        # This is required because the middleware stack is frozen after
        # the initialization and so it's too late to add our tracing
        # functionalities. The body of this block is always executed after
        # users code but before the last `Finisher`.
        initializer :datadog_config, before: :build_middleware_stack do |app|
          Datadog::Contrib::Rails::Framework.configure(config: app.config)

          # add the Rack middleware if auto instrumentation is enabled
          tracer = ::Rails.configuration.datadog_trace[:tracer]
          service = ::Rails.configuration.datadog_trace[:default_service]
          app.config.middleware.insert_before(
            0, Datadog::Contrib::Rack::TraceMiddleware,
            tracer: tracer, default_service: service
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
end
