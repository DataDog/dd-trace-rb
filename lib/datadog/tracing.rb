module Datadog
  # Datadog APM tracing public API.
  #
  # The Datadog teams ensures that public methods in this module
  # only receive backwards compatible changes, and breaking changes
  # will only occur in new major versions releases.
  module Tracing
    class << self
      # (see Datadog::Tracer#trace)
      # @public_api
      def trace(name, **kwargs, &block)
        tracer.trace(name, **kwargs, &block)
      end

      # The currently active {Datadog::Tracer} instance.
      #
      # The instance returned can change throughout the lifetime of the application.
      # This means it is not advisable to cache it.
      #
      # TODO: I think this next paragraph can be better written.
      #
      # Most of the functionality available through the {.tracer} instance is
      # also available in public methods in the {Datadog::Tracing} module.
      # It is preferable to use the public methods in the {Datadog::Tracing} when possible
      # as {Datadog::Tracing} strongly defines the tracing public API, and thus
      # we strive to no introduce breaking changes to {Datadog::Tracing} methods.
      #
      # @return [Datadog::Tracer] the active tracer
      # @public_api
      def tracer
        components.tracer
      end

      # TODO: should the logger be available publicly?
      # TODO: Are there any valid use cases for Datadog.logger.log(...)
      # TODO: from the host application?
      #
      # @public_api
      def logger
        Datadog.logger
      end

      # TODO: should the publicly exposed configuration be mutable?
      # @public_api
      def configuration
        Datadog.configuration
      end

      # Apply configuration changes to `ddtrace`. An example of a {.configure} call:
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
      # @yieldparam [Datadog::Configuration::Settings] c the mutable configuration object
      # @public_api
      def configure(&block)
        Datadog.configure(&block)
      end

      # The active, unfinished trace, representing the current instrumentation context.
      #
      # The active trace is thread-local.
      #
      # @return [Datadog::TraceSegment] the active trace
      # @return [nil] if no trace is active
      # @public_api
      def active_trace
        tracer.active_trace
      end

      # The active, unfinished span, representing the currently instrumented application section.
      #
      # The active span belongs to an {.active_trace}.
      #
      # @see .active_trace
      #
      # @return [Datadog::SpanOperation] the active span
      # @return [nil] if no trace is active, and thus no span is active
      # @public_api
      def active_span
        tracer.active_span
      end

      # If an active trace is present, forces it to be retained by the Datadog backend.
      #
      # Any sampling logic will not be able to change this decision.
      #
      # @return [void]
      # @public_api
      def keep!
        active_trace.keep!
      end

      # If an active trace is present, forces it to be dropped and not stored by the Datadog backend.
      #
      # TODO: should we mention billing? do we know if this directly affects billing?
      #
      # Any sampling logic will not be able to change this decision.
      #
      # @return [void]
      # @public_api
      def reject!
        active_trace.reject!
      end

      # Information about the currently active trace that allows
      # for another execution context to be linked to the active
      # trace.
      #
      # The most common use case is for propagating distributed
      # tracing information to downstream services.
      #
      # @return [Datadog::Correlation::Identifier] correlation object
      # @public_api
      def correlation
        tracer.active_correlation
      end

      # Textual representation of {.correlation}, which can be
      # added to individual log lines in order to correlate them with the active
      # trace.
      #
      # Example:
      #
      # ```
      # MyLogger.log("#{Datadog::Tracing.log_correlation}] My log message")
      # # dd.env=prod dd.service=billing dd.version=13.8 dd.trace_id=545847825299552251 dd.span_id=711755234730770098 My log message
      # ```
      #
      # @return [String] correlation information
      # @public_api
      def log_correlation
        correlation.to_s
      end

      # Gracefully shuts down the tracer.
      #
      # The public tracing API will still respond to method calls as usual
      # but might not internally perform the expected internal work after shutdown.
      #
      # This avoids errors being raised across the host application
      # during shutdown while allowing for the graceful decommission of resources.
      #
      # {.shutdown!} cannot be reversed.
      # @public_api
      def shutdown!
        components.shutdown!
      end

      # Returns the integration registry instance.
      #
      # This registry holds a reference to all integrations available
      # for tracing.
      #
      # Integrations registered in the registry can be activated as follows:
      #
      # ```
      # Datadog.configure do |c|
      #   c.use :my_registered_integration, **my_options
      # end
      # ```
      #
      # @return [Datadog::Contrib::Registry]
      # @public_api
      def registry
        Datadog::Contrib::REGISTRY
      end

      private

      def components
        # TODO: where will components live, given it hosts tracing and profiling components?
        Datadog.send(:components)
      end
    end
  end
end

# TODO: simple testing, remove me
# require 'ddtrace'
# Datadog.configure do |c|
#   c.diagnostics.debug = true
# end
#
# Datadog::Tracing.trace('a') {}
