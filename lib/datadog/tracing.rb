require 'datadog/core/configuration/validation_proxy'
require 'ddtrace/pipeline'

module Datadog
  # Datadog APM tracing public API.
  #
  # The Datadog team ensures that public methods in this module
  # only receive backwards compatible changes, and breaking changes
  # will only occur in new major versions releases.
  # @public_api
  module Tracing
    class << self
      # (see Datadog::Tracer#trace)
      # @public_api
      def trace(name, continue_from: nil, **span_options, &block)
        tracer.trace(name, continue_from: continue_from, **span_options, &block)
      end

      # (see Datadog::Tracer#continue_trace!)
      # @public_api
      def continue_trace!(digest, &block)
        tracer.continue_trace!(digest, &block)
      end

      # The tracer's internal logger instance.
      # All tracing log output is handled by this object.
      #
      # The logger can be configured through {.configure},
      # through {Datadog::Core::Configuration::Settings::DSL::Logger} options.
      #
      # @!attribute [r] logger
      # @public_api
      def logger
        Datadog.logger
      end

      # Current tracer configuration.
      #
      # Access to non-tracer configuration will raise an error.
      #
      # To modify the configuration, use {.configure}.
      #
      # @return [Datadog::Core::Configuration::Settings]
      # @!attribute [r] configuration
      # @public_api
      def configuration
        Datadog::Core::Configuration::ValidationProxy::Tracing.new(
          Datadog.send(:internal_configuration)
        )
      end

      # Apply configuration changes to `Datadog::Tracing`. An example of a {.configure} call:
      # ```
      # Datadog::Tracing.configure do |c|
      #   c.sampling.default_rate = 1.0
      #   c.instrument :aws
      #   c.instrument :rails
      #   c.instrument :sidekiq
      # end
      # ```
      # See {Datadog::Core::Configuration::Settings} for all available options, defaults, and
      # available environment variables for configuration.
      #
      # Only permits access to tracing configuration settings; others will raise an error.
      # If you wish to configure a global setting, use `Datadog.configure`` instead.
      # If you wish to configure a setting for a specific Datadog component (e.g. Profiling),
      # use the corresponding `Datadog::COMPONENT.configure` method instead.
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
      # See {Datadog::Core::Configuration::Settings} for all available options, defaults, and
      # available environment variables for configuration.
      #
      # Will raise errors if invalid setting is accessed.
      #
      # @yieldparam [Datadog::Core::Configuration::Settings] c the mutable configuration object
      # @return [void]
      # @public_api
      def configure
        # Wrap block with trace option validation
        wrapped_block = proc do |c|
          yield(Datadog::Core::Configuration::ValidationProxy::Tracing.new(c))
        end

        # Configure application normally
        Datadog.send(:internal_configure, &wrapped_block)
      end

      # (see Datadog::Tracer#active_trace)
      # @public_api
      def active_trace
        current_tracer = tracer
        return unless current_tracer

        current_tracer.active_trace
      end

      # (see Datadog::Tracer#active_span)
      # @public_api
      def active_span
        current_tracer = tracer
        return unless current_tracer

        current_tracer.active_span
      end

      # (see Datadog::TraceSegment#keep!)
      # If no trace is active, no action is taken.
      # @public_api
      def keep!
        trace = active_trace
        active_trace.keep! if trace
      end

      # (see Datadog::TraceSegment#reject!)
      # If no trace is active, no action is taken.
      # @public_api
      def reject!
        trace = active_trace
        active_trace.reject! if trace
      end

      # (see Datadog::Tracer#active_correlation)
      # @public_api
      def correlation
        current_tracer = tracer
        return unless current_tracer

        current_tracer.active_correlation
      end

      # Textual representation of {.correlation}, which can be
      # added to individual log lines in order to correlate them with the active
      # trace.
      #
      # Example:
      #
      # ```
      # MyLogger.log("#{Datadog::Tracing.log_correlation}] My message")
      # # dd.env=prod dd.service=auth dd.version=13.8 dd.trace_id=5458478252992251 dd.span_id=7117552347370098 My message
      # ```
      #
      # @return [String] correlation information
      # @public_api
      def log_correlation
        correlation.to_log_format
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
        current_tracer = tracer
        return unless current_tracer

        current_tracer.shutdown!
      end

      # (see Datadog::Pipeline.before_flush)
      def before_flush(*processors, &processor_block)
        Datadog::Pipeline.before_flush(*processors, &processor_block)
      end

      # Is the tracer collecting telemetry data in this process?
      # @return [Boolean] `true` if the tracer is collecting data in this process, otherwise `false`.
      def enabled?
        current_tracer = tracer
        return false unless current_tracer

        current_tracer.enabled
      end

      private

      # DEV: components hosts both tracing and profiling inner objects today
      def components
        Datadog.send(:components)
      end

      def tracer
        components.tracer
      end
    end
  end
end
