require 'forwardable'
require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'
require 'ddtrace/configuration/pin_setup'

module Datadog
  module Tracing
    # This class encapsulates all tracer runtime data and objects.
    #
    # Any stateful component or information that the tracer requires
    # to execute must be directly or indirectly managed by {Runtime}.
    #
    # Any object who's life cycle is not captured by {Runtime} should be
    # part of the generic tracer structure, unaffected by configuration
    # or runtime state.
    #
    # Creating a new {Runtime} will effectively configure and initialized a new
    # running instance of the tracer.
    #
    # Reconfiguration the {Runtime} will affect the running tracer instance without
    # a complete restart of the tracer internals.
    #
    # Destroying the {Runtime} will shutdown the current tracer instance.
    #
    # The tracer has started if and only if (iff) the {Runtime} has been started.
    # The tracer is shut down if and only if (iff) the {Runtime} is shut down.
    #
    # A production user of the tracer will only initialize at most a single {Runtime}
    # instance throughout the lifetime of the host application. Changes to the tracer
    # state will be handled by {Runtime#configure} invocations.
    #
    # TODO: {Runtime} currently indirectly manages the Profiler, though Components.
    # TODO: The Profiler life cycle management should be eventually extracted to its own runtime.
    class Runtime
      extend Forwardable

      attr_reader :configuration

      # Loads configuration and initializes basic components.
      def initialize(
        configuration = Configuration::Settings.new,
        components = Configuration::Components.new(configuration)
      )
        @configuration = configuration
        @components = components
      end

      # Triggers second step of component initialization.
      def startup!
        @components.startup!(@configuration)
      end

      def_delegators \
        :components,
        :health_metrics, :logger, :profiler, :runtime_metrics, :tracer

      # Alters configuration of the active {Runtime}.
      #
      # This call triggers component re-instantiation.
      def configure(target = configuration, opts = {})
        return Configuration::PinSetup.new(target, opts).call unless target.is_a?(Configuration::Settings)

        yield(target) if block_given?

        replace_components!(target, @components)
        startup!
      end

      # Gracefully shuts down all components.
      #
      # Components will still respond to method calls as usual,
      # but might not internally perform their work after shutdown.
      #
      # This avoids errors being raised across the host application
      # during shutdown, while allowing for graceful decommission of resources.
      def shutdown!
        @components.shutdown!
      end

      private

      attr_reader :components

      def replace_components!(configuration, old)
        @components = Configuration::Components.new(configuration)
        old.shutdown!(@components)
      end
    end
  end
end
