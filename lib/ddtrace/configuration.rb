require 'forwardable'
require 'thread'

require 'ddtrace/configuration/pin_setup'
require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'

module Datadog
  # Configuration provides a unique access point for configurations
  module Configuration
    extend Forwardable

    # Used to ensure that @components initialization/reconfiguration is performed one-at-a-time, by a single thread.
    #
    # This is important because components can end up being accessed from multiple application threads (for instance on
    # a threaded webserver), and we don't want their initialization to clash (for instance, starting two profilers...).
    #
    # Note that a Mutex **IS NOT** reentrant: the same thread cannot grab the same Mutex more than once.
    # This means below we are careful not to nest calls to methods that grab the lock.
    #
    # Every method that directly or indirectly accesses/mutates @components should be holding the lock (through
    # #safely_synchronize) while doing so.
    COMPONENTS_LOCK = Mutex.new
    private_constant :COMPONENTS_LOCK

    attr_writer :configuration

    def configuration
      @configuration ||= Settings.new
    end

    def configure(target = configuration, opts = {})
      if target.is_a?(Settings)
        yield(target) if block_given?

        safely_synchronize do
          # Build immutable components from settings
          @components ||= nil
          @components = if @components
                          replace_components!(target, @components)
                        else
                          build_components(target)
                        end
        end

        target
      else
        PinSetup.new(target, opts).call
      end
    end

    def_delegators \
      :components,
      :health_metrics,
      :runtime_metrics,
      :tracer

    def logger
      # avoid initializing components if they didn't already exist
      return logger_without_components unless components?

      @temp_logger = nil

      if COMPONENTS_LOCK.owned?
        # components are in the process of being replaced by this thread, avoid a deadlock and return the old logger
        @components.logger
      else
        # grab the lock and retrieve the latest logger
        components.logger
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
      safely_synchronize do
        @components.shutdown! if components?
      end
    end

    # Gracefully shuts down the tracer and disposes of component references,
    # allowing execution to start anew.
    #
    # In contrast with +#shutdown!+, components will be automatically
    # reinitialized after a reset.
    def reset!
      safely_synchronize do
        @components.shutdown! if components?
        @components = nil
      end
    end

    protected

    def components
      safely_synchronize do
        @components ||= build_components(configuration)
      end
    end

    private

    def safely_synchronize
      COMPONENTS_LOCK.synchronize do
        begin
          yield
        rescue ThreadError => e
          logger_without_components.error(
            'Detected deadlock during ddtrace initialization. ' \
            'Please report this at https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug' \
            "\n\tSource:\n\t#{e.backtrace.join("\n\t")}"
          )
          nil
        end
      end
    end

    def components?
      # This does not need to grab the COMPONENTS_LOCK because it's not returning the components
      (defined?(@components) && @components) != nil
    end

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

    def logger_without_components
      # Use default logger without initializing components.
      # This prevents recursive loops while initializing.
      # e.g. Get logger --> Build components --> Log message --> Repeat...
      @temp_logger ||= begin
        logger = configuration.logger.instance || Datadog::Logger.new($stdout)
        logger.level = configuration.diagnostics.debug ? ::Logger::DEBUG : configuration.logger.level
        logger
      end
    end
  end
end
