# typed: true
require 'ddtrace/configuration/agent_settings_resolver'
require 'ddtrace/diagnostics/health'
require 'ddtrace/logger'
require 'ddtrace/profiling'
require 'ddtrace/runtime/metrics'
require 'ddtrace/tracer'
require 'ddtrace/sync_writer'
require 'ddtrace/workers/runtime_metrics'

module Datadog
  module Configuration
    # Global components for the trace library.
    # rubocop:disable Metrics/ClassLength
    # rubocop:disable Layout/LineLength
    class Components
      class << self
        def build_health_metrics(settings)
          settings = settings.diagnostics.health_metrics
          options = { enabled: settings.enabled }
          options[:statsd] = settings.statsd unless settings.statsd.nil?

          Datadog::Diagnostics::Health::Metrics.new(**options)
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

          Datadog::Runtime::Metrics.new(**options)
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
            tags: build_tracer_tags(settings),
            sampler: PrioritySampler.new(
              base_sampler: AllSampler.new,
              post_sampler: Sampling::RuleSampler.new(
                rate_limit: settings.sampling.rate_limit,
                default_sample_rate: settings.sampling.default_rate
              )
            )
          )

          # TODO: We reconfigure the tracer here because it has way too many
          #       options it allows to mutate, and it's overwhelming to rewrite
          #       tracer initialization for now. Just reconfigure using the
          #       existing mutable #configure function. Remove when these components
          #       are extracted.
          tracer.configure(agent_settings: agent_settings, **build_tracer_options(settings, agent_settings))

          tracer
        end

        def build_profiler(settings, agent_settings, tracer)
          return unless Datadog::Profiling.supported? && settings.profiling.enabled

          unless defined?(Datadog::Profiling::Tasks::Setup)
            # In #1545 a user reported a NameError due to this constant being uninitialized
            # I've documented my suspicion on why that happened in
            # https://github.com/DataDog/dd-trace-rb/issues/1545#issuecomment-856049025
            #
            # > Thanks for the info! It seems to feed into my theory: there's two moments in the code where we check if
            # > profiler is "supported": 1) when loading ddtrace (inside preload) and 2) when starting the profile
            # > after Datadog.configure gets run.
            # > The problem is that the code assumes that both checks 1) and 2) will always reach the same conclusion:
            # > either profiler is supported, or profiler is not supported.
            # > In the problematic case, it looks like in your case check 1 decides that profiler is not
            # > supported => doesn't load it, and then check 2 decides that it is => assumes it is loaded and tries to
            # > start it.
            #
            # I was never able to validate if this was the issue or why exactly .supported? would change its mind BUT
            # just in case it happens again, I've left this check which avoids breaking the user's application AND
            # would instead direct them to report it to us instead, so that we can investigate what's wrong.
            #
            # TODO: As of June 2021, most checks in .supported? are related to the google-protobuf gem; so it's
            # very likely that it was the origin of the issue we saw. Thus, if, as planned we end up moving away from
            # protobuf OR enough time has passed and no users saw the issue again, we can remove this check altogether.
            Datadog.logger.error(
              'Profiling was marked as supported and enabled, but setup task was not loaded properly. ' \
              'Please report this at https://github.com/DataDog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug'
            )

            return
          end

          # Load extensions needed to support some of the Profiling features
          Datadog::Profiling::Tasks::Setup.new.run

          # NOTE: Please update the Initialization section of ProfilingDevelopment.md with any changes to this method

          trace_identifiers_helper = Datadog::Profiling::TraceIdentifiers::Helper.new(
            tracer: tracer,
            endpoint_collection_enabled: settings.profiling.advanced.endpoint.collection.enabled
          )

          # TODO: It's a bit weird to treat this collector differently from others. See the TODO on the
          # Datadog::Profiling::Recorder class for a discussion of this choice.
          if settings.profiling.advanced.code_provenance_enabled
            code_provenance_collector =
              Datadog::Profiling::Collectors::CodeProvenance.new
          end

          recorder = build_profiler_recorder(settings, code_provenance_collector)
          collectors = build_profiler_collectors(settings, recorder, trace_identifiers_helper)
          exporters = build_profiler_exporters(settings, agent_settings)
          scheduler = build_profiler_scheduler(settings, recorder, exporters)

          Datadog::Profiler.new(collectors, scheduler)
        end

        private

        def build_tracer_tags(settings)
          settings.tags.dup.tap do |tags|
            tags[Ext::Environment::TAG_ENV] = settings.env unless settings.env.nil?
            tags[Ext::Environment::TAG_VERSION] = settings.version unless settings.version.nil?
          end
        end

        def build_tracer_options(settings, agent_settings)
          tracer_options = {}.tap do |opts|
            tset = settings.tracer
            opts[:min_spans_before_partial_flush] = tset.partial_flush.min_spans_threshold unless tset.partial_flush.min_spans_threshold.nil?
            opts[:partial_flush] = tset.partial_flush.enabled unless tset.partial_flush.enabled.nil?
            opts[:priority_sampling] = tset.priority_sampling unless tset.priority_sampling.nil?
            opts[:sampler] = tset.sampler unless tset.sampler.nil?
            opts[:writer] = tset.writer unless tset.writer.nil?
            opts[:writer_options] = tset.writer_options if tset.writer.nil?
          end

          # Apply test mode settings if test mode is activated
          if settings.test_mode.enabled
            build_tracer_test_mode_options(tracer_options, settings, agent_settings)
          else
            tracer_options
          end
        end

        def build_tracer_test_mode_options(tracer_options, settings, agent_settings)
          tracer_options.tap do |opts|
            # Do not sample any spans for tests; all must be preserved.
            opts[:sampler] = Datadog::AllSampler.new

            # If context flush behavior is provided, use it instead.
            opts[:context_flush] = settings.test_mode.context_flush if settings.test_mode.context_flush

            # Flush traces synchronously, to guarantee they are written.
            writer_options = settings.test_mode.writer_options || {}
            writer_options[:agent_settings] = agent_settings if agent_settings
            opts[:writer] = Datadog::SyncWriter.new(writer_options)
          end
        end

        def build_profiler_recorder(settings, code_provenance_collector)
          event_classes = [Datadog::Profiling::Events::StackSample]

          Datadog::Profiling::Recorder.new(
            event_classes, settings.profiling.advanced.max_events, code_provenance_collector: code_provenance_collector
          )
        end

        def build_profiler_collectors(settings, recorder, trace_identifiers_helper)
          [
            Datadog::Profiling::Collectors::Stack.new(
              recorder,
              trace_identifiers_helper: trace_identifiers_helper,
              max_frames: settings.profiling.advanced.max_frames
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
        @profiler = self.class.build_profiler(settings, agent_settings, @tracer)

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
