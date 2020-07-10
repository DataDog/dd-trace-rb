require 'forwardable'

require 'ddtrace/configuration/pin_setup'
require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'

module Datadog
  # Configuration provides a unique access point for configurations
  module Configuration
    extend Forwardable

    attr_writer :configuration

    def configuration
      @configuration ||= Settings.new
    end

    def configure(target = configuration, opts = {})
      if target.is_a?(Settings)
        yield(target) if block_given?

        # Build immutable components from settings
        @components ||= nil
        @components = if @components
                        replace_components!(target, @components)
                      else
                        build_components(target)
                      end

        target
      else
        PinSetup.new(target, opts).call
      end
    end

    def_delegators \
      :components,
      :health_metrics,
      :profiler,
      :runtime_metrics,
      :tracer

    def logger
      if instance_variable_defined?(:@components) && @components
        @temp_logger = nil
        components.logger
      else
        # Use default logger without initializing components.
        # This prevents recursive loops while initializing.
        # e.g. Get logger --> Build components --> Log message --> Repeat...
        @temp_logger ||= begin
          logger = configuration.logger.instance || Datadog::Logger.new(STDOUT)
          logger.level = configuration.diagnostics.debug ? ::Logger::DEBUG : configuration.logger.level
          logger
        end
      end
    end

    # Gracefully shuts down all components.
    #
    # Components will still respond to method calls as usual,
    # but might not internally perform their work after shutdown.
    #
    # This avoids errors being raised across the host application
    # during shutdown, while allowing for graceful decommission of resources.
    #
    # Components won't be automatically reinitialized after a shutdown.
    def shutdown!
      components.shutdown! if instance_variable_defined?(:@components) && @components
    end

    # Gracefully shuts down the tracer and disposes of component references,
    # allowing execution to start anew.
    #
    # In contrast with +#shutdown!+, components will be automatically
    # reinitialized after a reset.
    def reset!
      shutdown!
      @components = nil
    end

    protected

    def components
      @components ||= build_components(configuration)
    end

    private

    def build_components(settings)
      components = Components.new(settings)
      components.startup!(settings)
      components
    end

    def replace_components!(settings, old)
      components = Components.new(settings)

      old.shutdown!(components)
      components.startup!(settings)
      components
    end
  end
end
