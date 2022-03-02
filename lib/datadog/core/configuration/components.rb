# typed: false
require 'datadog/core/configuration/agent_settings_resolver'
require 'datadog/core/diagnostics/environment_logger'
require 'datadog/core/diagnostics/health'
require 'datadog/core/logger'
require 'datadog/core/runtime/metrics'
require 'datadog/core/workers/runtime_metrics'

require 'datadog/tracing/tracer'
require 'datadog/tracing/flush'
require 'datadog/tracing/sync_writer'

require 'datadog/profiling'

module Datadog
  module Core
    module Configuration
      # Global components for the trace library.
      # rubocop:disable Metrics/ClassLength
      class Components
        class << self
          def build_health_metrics(settings)
            settings = settings.diagnostics.health_metrics
            options = { enabled: settings.enabled }
            options[:statsd] = settings.statsd unless settings.statsd.nil?

            Core::Diagnostics::Health::Metrics.new(**options)
          end

          def build_logger(settings)
            logger = settings.logger.instance || Core::Logger.new($stdout)
            logger.level = settings.diagnostics.debug ? ::Logger::DEBUG : settings.logger.level

            logger
          end

          def build_runtime_metrics(settings)
            options = { enabled: settings.runtime_metrics.enabled }
            options[:statsd] = settings.runtime_metrics.statsd unless settings.runtime_metrics.statsd.nil?
            options[:services] = [settings.service] unless settings.service.nil?

            Core::Runtime::Metrics.new(**options)
          end

          def build_runtime_metrics_worker(settings)
            # NOTE: Should we just ignore building the worker if its not enabled?
            options = settings.runtime_metrics.opts.merge(
              enabled: settings.runtime_metrics.enabled,
              metrics: build_runtime_metrics(settings)
            )

            Core::Workers::RuntimeMetrics.new(options)
          end

          def build_tracer(settings, agent_settings)
            # If a custom tracer has been provided, use it instead.
            # Ignore all other options (they should already be configured.)
            tracer = settings.tracing.instance
            return tracer unless tracer.nil?

            # Apply test mode settings if test mode is activated
            if settings.tracing.test_mode.enabled
              trace_flush = build_test_mode_trace_flush(settings)
              sampler = build_test_mode_sampler
              writer = build_test_mode_writer(settings, agent_settings)
            else
              trace_flush = build_trace_flush(settings)
              sampler = build_sampler(settings)
              writer = build_writer(settings, agent_settings)
            end

            subscribe_to_writer_events!(writer, sampler, settings.tracing.test_mode.enabled)

            Tracing::Tracer.new(
              default_service: settings.service,
              enabled: settings.tracing.enabled,
              trace_flush: trace_flush,
              sampler: sampler,
              writer: writer,
              tags: build_tracer_tags(settings),
            )
          end

          def build_trace_flush(settings)
            if settings.tracing.partial_flush.enabled
              Tracing::Flush::Partial.new(
                min_spans_before_partial_flush: settings.tracing.partial_flush.min_spans_threshold
              )
            else
              Tracing::Flush::Finished.new
            end
          end

          # TODO: Sampler should be a top-level component.
          # It is currently part of the Tracer initialization
          # process, but can take a variety of options (including
          # a fully custom instance) that makes the Tracer
          # initialization process complex.
          def build_sampler(settings)
            if (sampler = settings.tracing.sampler)
              if settings.tracing.priority_sampling == false
                sampler
              else
                ensure_priority_sampling(sampler, settings)
              end
            elsif settings.tracing.priority_sampling == false
              Tracing::Sampling::RuleSampler.new(
                rate_limit: settings.tracing.sampling.rate_limit,
                default_sample_rate: settings.tracing.sampling.default_rate
              )
            else
              Tracing::Sampling::PrioritySampler.new(
                base_sampler: Tracing::Sampling::AllSampler.new,
                post_sampler: Tracing::Sampling::RuleSampler.new(
                  rate_limit: settings.tracing.sampling.rate_limit,
                  default_sample_rate: settings.tracing.sampling.default_rate
                )
              )
            end
          end

          def ensure_priority_sampling(sampler, settings)
            if sampler.is_a?(Tracing::Sampling::PrioritySampler)
              sampler
            else
              Tracing::Sampling::PrioritySampler.new(
                base_sampler: sampler,
                post_sampler: Tracing::Sampling::RuleSampler.new(
                  rate_limit: settings.tracing.sampling.rate_limit,
                  default_sample_rate: settings.tracing.sampling.default_rate
                )
              )
            end
          end

          # TODO: Writer should be a top-level component.
          # It is currently part of the Tracer initialization
          # process, but can take a variety of options (including
          # a fully custom instance) that makes the Tracer
          # initialization process complex.
          def build_writer(settings, agent_settings)
            if (writer = settings.tracing.writer)
              return writer
            end

            Tracing::Writer.new(agent_settings: agent_settings, **settings.tracing.writer_options)
          end

          def subscribe_to_writer_events!(writer, sampler, test_mode)
            return unless writer.respond_to?(:events) # Check if it's a custom, external writer

            writer.events.after_send.subscribe(&WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK)

            return unless sampler.is_a?(Tracing::Sampling::PrioritySampler)

            # DEV: We need to ignore priority sampling updates coming from the agent in test mode
            # because test mode wants to *unconditionally* sample all traces.
            #
            # This can cause trace metrics to be overestimated, but that's a trade-off we take
            # here to achieve 100% sampling rate.
            return if test_mode

            writer.events.after_send.subscribe(&writer_update_priority_sampler_rates_callback(sampler))
          end

          WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK = lambda do |_, responses|
            Core::Diagnostics::EnvironmentLogger.log!(responses)
          end

          # Create new lambda for writer callback,
          # capture the current sampler in the callback closure.
          def writer_update_priority_sampler_rates_callback(sampler)
            lambda do |_, responses|
              response = responses.last

              next unless response && !response.internal_error? && response.service_rates

              sampler.update(response.service_rates)
            end
          end

          def build_profiler(settings, agent_settings, tracer)
            return unless Profiling.supported? && settings.profiling.enabled

            unless defined?(Profiling::Tasks::Setup)
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
            Profiling::Tasks::Setup.new.run

            # NOTE: Please update the Initialization section of ProfilingDevelopment.md with any changes to this method

            trace_identifiers_helper = Profiling::TraceIdentifiers::Helper.new(
              tracer: tracer,
              endpoint_collection_enabled: settings.profiling.advanced.endpoint.collection.enabled
            )

            # TODO: It's a bit weird to treat this collector differently from others. See the TODO on the
            # Datadog::Profiling::Recorder class for a discussion of this choice.
            if settings.profiling.advanced.code_provenance_enabled
              code_provenance_collector =
                Profiling::Collectors::CodeProvenance.new
            end

            recorder = build_profiler_recorder(settings, code_provenance_collector)
            collectors = build_profiler_collectors(settings, recorder, trace_identifiers_helper)
            transport = build_profiler_transport(settings, agent_settings)
            scheduler = build_profiler_scheduler(settings, recorder, transport)

            Profiling::Profiler.new(collectors, scheduler)
          end

          private

          def build_tracer_tags(settings)
            settings.tags.dup.tap do |tags|
              tags[Core::Environment::Ext::TAG_ENV] = settings.env unless settings.env.nil?
              tags[Core::Environment::Ext::TAG_VERSION] = settings.version unless settings.version.nil?
            end
          end

          def build_test_mode_trace_flush(settings)
            # If context flush behavior is provided, use it instead.
            settings.tracing.test_mode.trace_flush || build_trace_flush(settings)
          end

          def build_test_mode_sampler
            # Do not sample any spans for tests; all must be preserved.
            # Set priority sampler to ensure the agent doesn't drop any traces.
            Tracing::Sampling::PrioritySampler.new(
              base_sampler: Tracing::Sampling::AllSampler.new,
              post_sampler: Tracing::Sampling::AllSampler.new
            )
          end

          def build_test_mode_writer(settings, agent_settings)
            # Flush traces synchronously, to guarantee they are written.
            writer_options = settings.tracing.test_mode.writer_options || {}
            Tracing::SyncWriter.new(agent_settings: agent_settings, **writer_options)
          end

          def build_profiler_recorder(settings, code_provenance_collector)
            event_classes = [Profiling::Events::StackSample]

            Profiling::Recorder.new(
              event_classes,
              settings.profiling.advanced.max_events,
              code_provenance_collector: code_provenance_collector
            )
          end

          def build_profiler_collectors(settings, recorder, trace_identifiers_helper)
            [
              Profiling::Collectors::Stack.new(
                recorder,
                trace_identifiers_helper: trace_identifiers_helper,
                max_frames: settings.profiling.advanced.max_frames
                # TODO: Provide proc that identifies Datadog worker threads?
                # ignore_thread: settings.profiling.ignore_profiler
              )
            ]
          end

          def build_profiler_transport(settings, agent_settings)
            settings.profiling.exporter.transport ||
              Profiling::HttpTransport.new(
                agent_settings: agent_settings,
                site: settings.site,
                api_key: settings.api_key,
                upload_timeout_seconds: settings.profiling.upload.timeout_seconds,
              )
          end

          def build_profiler_scheduler(_settings, recorder, transport)
            Profiling::Scheduler.new(recorder: recorder, transport: transport)
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
              unsupported_reason = Profiling.unsupported_reason
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
      # rubocop:enable Metrics/ClassLength
    end
  end
end
