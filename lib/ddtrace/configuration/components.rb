require 'ddtrace/tracer'

module Datadog
  module Configuration
    # Global components for the trace library.
    # rubocop:disable Metrics/LineLength
    class Components
      def initialize(settings)
        # Tracer
        @tracer = build_tracer(settings)

        # Runtime metrics
        build_runtime_metrics(settings)

        # Health metrics
        @health_metrics = build_health_metrics(settings)
      end

      attr_reader \
        :health_metrics,
        :tracer

      def runtime_metrics
        tracer.writer.runtime_metrics
      end

      private

      def build_tracer(settings)
        # If a custom tracer has been provided, use it instead.
        # Ignore all other options (they should already be configured.)
        return settings.tracer.instance unless settings.tracer.instance.nil?

        tracer = Tracer.new(
          default_service: settings.service,
          enabled: settings.tracer.enabled,
          partial_flush: settings.tracer.partial_flush,
          tags: build_tracer_tags(settings)
        )

        # TODO: We reconfigure the tracer here because it has way too many
        #       options it allows to mutate, and it's overwhelming to rewrite
        #       tracer initialization for now. Just reconfigure using the
        #       existing mutable #configure function. Remove when these components
        #       are extracted.
        tracer.configure(build_tracer_options(settings))

        tracer
      end

      def build_tracer_tags(settings)
        settings.tags.dup.tap do |tags|
          tags['env'] = settings.env unless settings.env.nil?
          tags['version'] = settings.version unless settings.version.nil?
        end
      end

      def build_tracer_options(settings)
        settings = settings.tracer

        {}.tap do |opts|
          opts[:hostname] = settings.hostname unless settings.hostname.nil?
          opts[:min_spans_before_partial_flush] = settings.partial_flush.min_spans_threshold unless settings.partial_flush.min_spans_threshold.nil?
          opts[:partial_flush] = settings.partial_flush.enabled unless settings.partial_flush.enabled.nil?
          opts[:port] = settings.port unless settings.port.nil?
          opts[:priority_sampling] = settings.priority_sampling unless settings.priority_sampling.nil?
          opts[:sampler] = settings.sampler unless settings.sampler.nil?
          opts[:transport_options] = settings.transport_options
          opts[:writer] = settings.writer unless settings.writer.nil?
          opts[:writer_options] = settings.writer_options if settings.writer.nil?
        end
      end

      def build_runtime_metrics(settings)
        settings = settings.runtime_metrics
        options = { enabled: settings.enabled }
        options[:statsd] = settings.statsd unless settings.statsd.nil?

        # TODO: We reconfigure runtime metrics here because it is too deeply nested
        #       within the tracer/writer. Build a new runtime metrics instance when
        #       runtime metrics are extracted from tracer/writer.
        runtime_metrics.configure(options)
      end

      def build_health_metrics(settings)
        settings = settings.diagnostics.health_metrics
        options = { enabled: settings.enabled }
        options[:statsd] = settings.statsd unless settings.statsd.nil?

        Datadog::Diagnostics::Health::Metrics.new(options)
      end
    end
  end
end
