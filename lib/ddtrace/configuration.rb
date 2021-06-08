require 'forwardable'
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
    # This means below we are careful not to nest calls to methods that would trigger initialization and grab the lock.
    #
    # Every method that directly or indirectly mutates @components should be holding the lock (through
    # #safely_synchronize) while doing so.
    COMPONENTS_WRITE_LOCK = Mutex.new
    private_constant :COMPONENTS_WRITE_LOCK

    # We use a separate lock when reading the @components, so that they continue to be accessible during reconfiguration.
    # This was needed because we ran into several issues where we still needed to read the old
    # components while the COMPONENTS_WRITE_LOCK was being held (see https://github.com/DataDog/dd-trace-rb/pull/1387
    # and https://github.com/DataDog/dd-trace-rb/pull/1373#issuecomment-799593022 ).
    #
    # Technically on MRI we could get away without this lock, but on non-MRI Rubies, we may run into issues because
    # we fall into the "UnsafeDCLFactory" case of https://shipilev.net/blog/2014/safe-public-construction/ .
    # Specifically, on JRuby reads from the @components do NOT have volatile semantics, and on TruffleRuby they do
    # BUT just as an implementation detail, see https://github.com/jruby/jruby/wiki/Concurrency-in-jruby#volatility and
    # https://github.com/DataDog/dd-trace-rb/pull/1329#issuecomment-776750377 .
    # Concurrency is hard.
    COMPONENTS_READ_LOCK = Mutex.new
    private_constant :COMPONENTS_READ_LOCK

    attr_writer :configuration

    def configuration
      @configuration ||= Settings.new
    end

    def configure(target = configuration, opts = {})
      if target.is_a?(Settings)
        yield(target) if block_given?

        safely_synchronize do |write_components|
          write_components.call(
            if components?
              replace_components!(target, @components)
            else
              build_components(target)
            end
          )
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
      # avoid initializing components if they didn't already exist
      current_components = components(allow_initialization: false)

      if current_components
        @temp_logger = nil
        current_components.logger
      else
        logger_without_components
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

    protected

    def components(allow_initialization: true)
      current_components = COMPONENTS_READ_LOCK.synchronize { defined?(@components) && @components }
      return current_components if current_components || !allow_initialization

      safely_synchronize do |write_components|
        (defined?(@components) && @components) || write_components.call(build_components(configuration))
      end
    end

    private

    # Gracefully shuts down the tracer and disposes of component references,
    # allowing execution to start anew.
    #
    # In contrast with +#shutdown!+, components will be automatically
    # reinitialized after a reset.
    #
    # Used internally to ensure a clean environment between test runs.
    def reset!
      safely_synchronize do |write_components|
        @components.shutdown! if components?
        write_components.call(nil)
        configuration.reset!
      end
    end

    def safely_synchronize
      # Writes to @components should only happen through this proc. Because this proc is only accessible to callers of
      # safely_synchronize, this forces all writers to go through this method.
      write_components = proc do |new_value|
        COMPONENTS_READ_LOCK.synchronize { @components = new_value }
      end

      COMPONENTS_WRITE_LOCK.synchronize do
        begin
          yield write_components
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
      # This does not need to grab the COMPONENTS_READ_LOCK because it's not returning the components
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
      # This enables logging during initialization, otherwise we'd run into deadlocks.
      @temp_logger ||= begin
        logger = configuration.logger.instance || Datadog::Logger.new($stdout)
        logger.level = configuration.diagnostics.debug ? ::Logger::DEBUG : configuration.logger.level
        logger
      end
    end
  end
end
