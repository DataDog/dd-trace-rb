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
  def self.tracer
    @tracer
  end

  def self.tracer=(_tracer)
    @tracer = tracer
  end
end

# Datadog auto instrumentation for frameworks
if defined?(Rails::VERSION)
  if Rails::VERSION::MAJOR.to_i >= 3
    require 'ddtrace/contrib/rails/framework'
    require 'ddtrace/contrib/elasticsearch/core' # TODO[Aaditya] only if elasticsearch here, with right version

    module Datadog
      # Run the auto instrumentation directly after the initialization of the application and
      # after the application initializers in config/initializers are run
      class Railtie < Rails::Railtie
        config.after_initialize do |app|
          Datadog::Contrib::Rails::Framework.configure(config: app.config)
          Datadog::Contrib::Rails::Framework.auto_instrument()
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
