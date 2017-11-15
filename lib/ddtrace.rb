require 'ddtrace/registry'
require 'ddtrace/pin'
require 'ddtrace/tracer'
require 'ddtrace/error'
require 'ddtrace/pipeline'
require 'ddtrace/configuration'

# \Datadog global namespace that includes all tracing functionality for Tracer and Span classes.
module Datadog
  @tracer = Tracer.new
  @registry = Registry.new

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

  def self.registry
    @registry
  end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end
  end
end

# Monkey currently is responsible for loading all contributions, which in turn
# rely on the registry defined above. We should make our code less dependent on
# the load order, by letting things be lazily loaded while keeping
# thread-safety.
require 'ddtrace/monkey'

# Datadog auto instrumentation for frameworks
if defined?(Rails::VERSION)
  if !ENV['DISABLE_DATADOG_RAILS']
    if Rails::VERSION::MAJOR.to_i >= 3
      require 'ddtrace/contrib/rails/framework'
      require 'ddtrace/contrib/rails/middlewares'

      module Datadog
        # Railtie class initializes
        class Railtie < Rails::Railtie
          # add instrumentation middlewares
          options = {}
          config.app_middleware.insert_before(0, Datadog::Contrib::Rack::TraceMiddleware, options)
          config.app_middleware.use(Datadog::Contrib::Rails::ExceptionMiddleware)

          # auto instrument Rails and third party components after
          # the framework initialization
          config.after_initialize do |app|
            Datadog::Contrib::Rails::Framework.configure(config: app.config)
            Datadog::Contrib::Rails::Framework.auto_instrument()
            Datadog::Contrib::Rails::Framework.auto_instrument_grape()

            # override Rack Middleware configurations with Rails
            options.update(::Rails.configuration.datadog_trace)
            Datadog::Contrib::Rails::Framework.auto_instrument_redis(app.config.datadog_trace)
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
