require 'ddtrace/diagnostics/health'
require 'ddtrace/logger'
require 'ddtrace/runtime/metrics'
require 'ddtrace/sampling/priority_sampling'
require 'ddtrace/tracer'
require 'ddtrace/workers/trace_writer'
require 'ddtrace/workers/runtime_metrics'
require 'ddtrace/writer'

module Datadog
  module Configuration
    # Global components for the trace library.
    class Components
      class << self
        def build_health_metrics(settings)
          settings = settings.diagnostics.health_metrics
          options = { enabled: settings.enabled }
          options[:statsd] = settings.statsd unless settings.statsd.nil?

          Datadog::Diagnostics::Health::Metrics.new(options)
        end

        def build_logger(settings)
          logger = settings.logger.instance || Datadog::Logger.new($stdout)
          logger.level = settings.diagnostics.debug ? ::Logger::DEBUG : settings.logger.level

          logger
        end

        def build_runtime_metrics(settings)
          options = { enabled: settings.runtime_metrics.enabled }
          options[:statsd] = settings.runtime_metrics.statsd unless settings.runtime_metrics.statsd.nil?
          options[:services] = [settings.service] unless settings.service.nil?

          Datadog::Runtime::Metrics.new(options)
        end

        def build_runtime_metrics_worker(settings)
          # NOTE: Should we just ignore building the worker if its not enabled?
          options = settings.runtime_metrics.opts.merge(
            enabled: settings.runtime_metrics.enabled,
            metrics: build_runtime_metrics(settings)
          )

          Datadog::Workers::RuntimeMetrics.new(options)
        end

        def build_trace_writer(settings)
          # If a custom writer has been provided, use it instead.
          # Ignore all other options (they should already be configured.)
          trace_writer = settings.trace_writer.instance
          return trace_writer unless trace_writer.nil?

          options = settings.trace_writer.opts.dup

          if !settings.trace_writer.transport.nil?
            options[:transport] = settings.trace_writer.transport
          else
            transport_options = settings.trace_writer.transport_options.dup
            transport_options[:hostname] = settings.trace_writer.hostname unless settings.trace_writer.hostname.nil?
            transport_options[:port] = settings.trace_writer.port unless settings.trace_writer.port.nil?

            options[:transport_options] = transport_options
          end

          # TODO: Switch to Datadog::Workers::AsyncTraceWriter
          Datadog::Writer.new(options)
        end

        def build_tracer(settings)
          # If a custom tracer has been provided, use it instead.
          # Ignore all other options (they should already be configured.)
          tracer = settings.tracer.instance
          return tracer unless tracer.nil?

          options = settings.tracer.opts.merge(
            default_service: settings.service,
            enabled: settings.tracer.enabled,
            partial_flush: settings.tracer.partial_flush.enabled,
            tags: build_tracer_tags(settings)
          )

          unless settings.tracer.partial_flush.min_spans_threshold.nil?
            options[:min_spans_before_partial_flush] = settings.tracer.partial_flush.min_spans_threshold
          end

          options[:sampler] = settings.sampling.sampler unless settings.sampling.sampler.nil?

          Datadog::Tracer.new(options)
        end

        private

        def build_tracer_tags(settings)
          settings.tags.dup.tap do |tags|
            tags['env'] = settings.env unless settings.env.nil?
            tags['version'] = settings.version unless settings.version.nil?
          end
        end
      end

      attr_reader \
        :health_metrics,
        :logger,
        :runtime_metrics,
        :trace_writer,
        :tracer

      def initialize(settings)
        # Logger
        @logger = self.class.build_logger(settings)

        # Tracer
        @tracer = self.class.build_tracer(settings)

        # Trace writer
        @trace_writer = self.class.build_trace_writer(settings)

        # Runtime metrics
        @runtime_metrics = self.class.build_runtime_metrics_worker(settings)

        # Health metrics
        @health_metrics = self.class.build_health_metrics(settings)

        # Publish traces to trace writer
        tracer.trace_completed.subscribe(:trace_writer) do |trace|
          trace_writer.write(trace)
        end

        if settings.runtime_metrics.enabled
          # Publish updates to the runtime metrics worker
          tracer.trace_completed.subscribe(:runtime_metrics) do |trace|
            runtime_metrics.associate_with_span(trace.first) unless trace.nil?
            runtime_metrics.perform
          end
        end

        if settings.sampling.priority_sampling
          # Activate priority sampling
          Datadog::Sampling::PrioritySampling.activate!(
            tracer: tracer,
            trace_writer: trace_writer
          )
        else
          # Deactivate priority sampling
          Datadog::Sampling::PrioritySampling.deactivate!(
            tracer: tracer,
            trace_writer: trace_writer,
            sampler: settings.sampling.sampler
          )
        end
      end

      # Starts up components
      def startup!(settings); end

      # Shuts down all the components in use.
      # If it has another instance to compare to, it will compare
      # and avoid tearing down parts still in use.
      def shutdown!(replacement = nil)
        # Stop the old trace writer, unless it's still being used.
        # (e.g. a custom trace writer instance passed in.)
        # Note, it could be a synchronous writer that doesn't "stop."
        unless replacement && trace_writer == replacement.trace_writer
          trace_writer.enabled = false if trace_writer.respond_to?(:enabled=)
          trace_writer.stop if trace_writer.respond_to?(:stop)
        end

        # Shutdown workers
        runtime_metrics.enabled = false
        runtime_metrics.stop(true)

        # Shutdown the old metrics, unless they are still being used.
        # (e.g. custom Statsd instances.)
        old_statsd = [
          runtime_metrics.metrics.statsd,
          health_metrics.statsd
        ].compact.uniq

        new_statsd =  if replacement
                        [
                          replacement.runtime_metrics.metrics.statsd,
                          replacement.health_metrics.statsd
                        ].compact.uniq
                      else
                        []
                      end

        unused_statsd = (old_statsd - (old_statsd & new_statsd))
        unused_statsd.each(&:close)
      end
    end
  end
end
