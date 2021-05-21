require 'ddtrace/configuration/agent_settings_resolver'
require 'ddtrace/diagnostics/health'
require 'ddtrace/logger'
require 'ddtrace/profiling'
require 'ddtrace/runtime/metrics'
require 'ddtrace/tracer'
require 'ddtrace/workers/runtime_metrics'

module Datadog
  module Configuration
    # Global components for the trace library.
    # rubocop:disable Layout/LineLength
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

        def build_tracer(settings, agent_settings)
          # If a custom tracer has been provided, use it instead.
          # Ignore all other options (they should already be configured.)
          tracer = settings.tracer.instance
          return tracer unless tracer.nil?

          tracer = Tracer.new(
            default_service: settings.service,
            enabled: settings.tracer.enabled,
            partial_flush: settings.tracer.partial_flush.enabled,
            tags: build_tracer_tags(settings)
          )

          # TODO: We reconfigure the tracer here because it has way too many
          #       options it allows to mutate, and it's overwhelming to rewrite
          #       tracer initialization for now. Just reconfigure using the
          #       existing mutable #configure function. Remove when these components
          #       are extracted.
          tracer.configure(agent_settings: agent_settings, **build_tracer_options(settings))

          tracer
        end

        def build_profiler(settings, agent_settings)
          return unless Datadog::Profiling.supported? && settings.profiling.enabled

          # Load extensions needed to support some of the Profiling features
          Datadog::Profiling::Tasks::Setup.new.run

          # NOTE: Please update the Initialization section of ProfilingDevelopment.md with any changes to this method

          recorder = build_profiler_recorder(settings)
          collectors = build_profiler_collectors(settings, recorder)
          exporters = build_profiler_exporters(settings, agent_settings)
          scheduler = build_profiler_scheduler(settings, recorder, exporters)

          Datadog::Profiler.new(collectors, scheduler)
        end

        private

        def build_tracer_tags(settings)
          settings.tags.dup.tap do |tags|
            tags['env'] = settings.env unless settings.env.nil?
            tags['version'] = settings.version unless settings.version.nil?
          end
        end

        def build_tracer_options(settings)
          settings = settings.tracer

          {}.tap do |opts|
            opts[:min_spans_before_partial_flush] = settings.partial_flush.min_spans_threshold unless settings.partial_flush.min_spans_threshold.nil?
            opts[:partial_flush] = settings.partial_flush.enabled unless settings.partial_flush.enabled.nil?
            opts[:priority_sampling] = settings.priority_sampling unless settings.priority_sampling.nil?
            opts[:sampler] = settings.sampler unless settings.sampler.nil?
            opts[:writer] = settings.writer unless settings.writer.nil?
            opts[:writer_options] = settings.writer_options if settings.writer.nil?
          end
        end

        def build_profiler_recorder(settings)
          event_classes = [Datadog::Profiling::Events::StackSample]

          Datadog::Profiling::Recorder.new(event_classes, settings.profiling.max_events)
        end

        def build_profiler_collectors(settings, recorder)
          [
            Datadog::Profiling::Collectors::Stack.new(
              recorder,
              max_frames: settings.profiling.max_frames
              # TODO: Provide proc that identifies Datadog worker threads?
              # ignore_thread: settings.profiling.ignore_profiler
            )
          ]
        end

        def build_profiler_exporters(settings, agent_settings)
          transport =
            settings.profiling.exporter.transport || Datadog::Profiling::Transport::HTTP.default(
              agent_settings: agent_settings,
              site: settings.site,
              api_key: settings.api_key,
              profiling_upload_timeout_seconds: settings.profiling.upload.timeout_seconds
            )

          [Datadog::Profiling::Exporter.new(transport)]
        end

        def build_profiler_scheduler(settings, recorder, exporters)
          Datadog::Profiling::Scheduler.new(recorder, exporters)
        end
      end

      attr_reader \
        :health_metrics,
        :logger,
        :profiler,
        :runtime_metrics,
        :tracer

      def initialize(settings)
        # Logger
        @logger = self.class.build_logger(settings)

        agent_settings = AgentSettingsResolver.call(settings, logger: @logger)

        # Tracer
        @tracer = self.class.build_tracer(settings, agent_settings)

        # Profiler
        @profiler = self.class.build_profiler(settings, agent_settings)

        # Runtime metrics
        @runtime_metrics = self.class.build_runtime_metrics_worker(settings)

        # Health metrics
        @health_metrics = self.class.build_health_metrics(settings)
      end

      # Starts up components
      def startup!(settings)
        if settings.profiling.enabled
          if profiler
            @logger.debug('Profiling started')
            profiler.start
          else
            # Display a warning for users who expected profiling to be enabled
            unsupported_reason = Datadog::Profiling.unsupported_reason
            logger.warn("Profiling was requested but is not supported, profiling disabled: #{unsupported_reason}")
          end
        else
          @logger.debug('Profiling is disabled')
        end
      end

      # Shuts down all the components in use.
      # If it has another instance to compare to, it will compare
      # and avoid tearing down parts still in use.
      def shutdown!(replacement = nil)
        # Shutdown the old tracer, unless it's still being used.
        # (e.g. a custom tracer instance passed in.)
        tracer.shutdown! unless replacement && tracer == replacement.tracer

        # Shutdown old profiler
        profiler.shutdown! unless profiler.nil?

        # Shutdown workers
        runtime_metrics.stop(true, close_metrics: false)

        # Shutdown the old metrics, unless they are still being used.
        # (e.g. custom Statsd instances.)
        #
        # TODO: This violates the encapsulation created by Runtime::Metrics and
        # Health::Metrics, by directly manipulating `statsd` and changing
        # it's lifecycle management.
        # If we need to directly have ownership of `statsd` lifecycle, we should
        # have direct ownership of it.
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
