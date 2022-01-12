# typed: true
require 'forwardable'
require 'ddtrace/configuration/pin_setup'
require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'

module Datadog
  # Configuration provides a unique access point for configurations
  module Configuration # rubocop:disable Metrics/ModuleLength
    include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
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

    # Apply configuration changes to `ddtrace`. An example of a {.configure} call:
    #
    # ```
    # Datadog.configure do |c|
    #   c.sampling.default_rate = 1.0
    #   c.use :aws
    #   c.use :rails
    #   c.use :sidekiq
    #   # c.diagnostics.debug = true # Enables debug output
    # end
    # ```
    #
    # Because many configuration changes require restarting internal components,
    # invoking {.configure} is the only safe way to change `ddtrace` configuration.
    #
    # Successive calls to {.configure} maintain the previous configuration values:
    # configuration is additive between {.configure} calls.
    #
    # The yielded configuration `c` comes pre-populated from environment variables, if
    # any are applicable.
    #
    # See {Datadog::Configuration::Settings} for all available options, defaults, and
    # available environment variables for configuration.
    #
    # @param [Datadog::Configuration::Settings] configuration the base configuration object. Provide a custom instance
    #   if you are managing the configuration yourself. By default, the global configuration object is used.
    # @yieldparam [Datadog::Configuration::Settings] c the mutable configuration object
    def configure(configuration = self.configuration)
      yield(configuration)

      safely_synchronize do |write_components|
        write_components.call(
          if components?
            replace_components!(configuration, @components)
          else
            build_components(configuration)
          end
        )
      end

      configuration
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
            "\n\tSource:\n\t#{Array(e.backtrace).join("\n\t")}"
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

    # Called from our at_exit hook whenever there was a pending Interrupt exception (e.g. typically due to ctrl+c)
    # to print a nice message whenever we're taking a bit longer than usual to finish the process.
    def handle_interrupt_shutdown!
      logger = Datadog.logger
      shutdown_thread = Thread.new { shutdown! }
      print_message_treshold_seconds = 0.2

      slow_shutdown = shutdown_thread.join(print_message_treshold_seconds).nil?

      if slow_shutdown
        logger.info 'Reporting remaining data... Press ctrl+c to exit immediately.'
        shutdown_thread.join
      end

      nil
    end
  end
end
