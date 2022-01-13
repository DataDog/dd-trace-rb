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

      # The currently active {Datadog::Tracer} instance.
      #
      # The instance returned can change throughout the lifetime of the application.
      # This means it is not advisable to cache it.
      #
      # The tracer can be configured through {.configure},
      # through {Datadog::Configuration::Settings::DSL::Tracer} options.
      #
      # @deprecated Use public API methods available in {Datadog::Tracing} instead.
      # @return [Datadog::Tracer] the active tracer
      # @!attribute [r] tracer
      # @public_api
      def tracer
        components.tracer
      end

      # The tracer's internal logger instance.
      # All tracing log output is handled by this object.
      #
      # The logger can be configured through {.configure},
      # through {Datadog::Configuration::Settings::DSL::Logger} options.
      #
      # @!attribute [r] logger
      # @public_api
      def logger
        Datadog.logger
      end

      # (see Datadog::Tracer#active_trace)
      # @public_api
      def active_trace
        return unless tracer

        tracer.active_trace
      end

      # (see Datadog::Tracer#active_span)
      # @public_api
      def active_span
        return unless tracer

        tracer.active_span
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
        return unless tracer

        tracer.active_correlation
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
        return unless tracer

        tracer.shutdown!
      end

      # The global integration registry.
      #
      # This registry holds a reference to all integrations available
      # to the tracer.
      #
      # Integrations registered in the {.registry} can be activated as follows:
      #
      # ```
      # Datadog::Tracing.configure do |c|
      #   c.use :my_registered_integration, **my_options
      # end
      # ```
      #
      # New integrations can be registered by implementing the {Datadog::Contrib::Integration} interface.
      #
      # @return [Datadog::Contrib::Registry]
      # @!attribute [r] registry
      # @public_api
      def registry
        Datadog::Contrib::REGISTRY
      end

      # (see Datadog::Pipeline.before_flush)
      def before_flush(*processors, &processor_block)
        Datadog::Pipeline.before_flush(*processors, &processor_block)
      end

      # Is the tracer collecting telemetry data in this process?
      # @return [Boolean] `true` if the tracer is collecting data in this process, otherwise `false`.
      def enabled?
        return false unless tracer

        tracer.enabled
      end

      private

      # DEV: components hosts both tracing and profiling inner objects today
      def components
        Datadog.send(:components)
      end
    end
  end
end
