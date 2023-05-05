# frozen_string_literal: true

require_relative 'tracer'
require_relative 'flush'
require_relative 'sync_writer'
require_relative 'sampling/span/rule_parser'
require_relative 'sampling/span/sampler'

module Datadog
  module Tracing
    # Tracing component
    module Component
      def build_tracer(settings, agent_settings)
        # If a custom tracer has been provided, use it instead.
        # Ignore all other options (they should already be configured.)
        # tracer = settings.tracing.instance
        # return tracer unless tracer.nil?
        #
        # # Apply test mode settings if test mode is activated
        # if settings.tracing.test_mode.enabled
        #   trace_flush = build_test_mode_trace_flush(settings)
        #   sampler = build_test_mode_sampler
        #   writer = build_test_mode_writer(settings, agent_settings)
        # else
        #   trace_flush = build_trace_flush(settings)
        #   sampler = build_sampler(settings)
        #   writer = build_writer(settings, agent_settings)
        # end
        #
        # subscribe_to_writer_events!(writer, sampler, settings.tracing.test_mode.enabled)
        #
        # Tracing::Tracer.new(
        #   default_service: settings.service,
        #   enabled: settings.tracing.enabled,
        #   trace_flush: trace_flush,
        #   sampler: sampler,
        #   span_sampler: build_span_sampler(settings),
        #   writer: writer,
        #   tags: build_tracer_tags(settings),
        # )

        Datadog::Core.dependency_registry.resolve_component(:tracer)
      end

      # def build_trace_flush(settings)
      #   if settings.tracing.partial_flush.enabled
      #     Tracing::Flush::Partial.new(
      #       min_spans_before_partial_flush: settings.tracing.partial_flush.min_spans_threshold
      #     )
      #   else
      #     Tracing::Flush::Finished.new
      #   end
      # end


      module Tags
        extend Core::Dependency

        setting(:tags, 'tags')
        setting(:env, 'env')
        setting(:version, 'version')
        def self.new(tags, env, version)
          tags.dup.tap do |tags|
            tags[Core::Environment::Ext::TAG_ENV] = env unless env.nil?
            tags[Core::Environment::Ext::TAG_VERSION] = version unless version.nil?
          end
        end
      end

      class TraceFlush
        extend Core::Dependency

        setting(:test_mode, 'tracing.test_mode.enabled')
        setting(:test_mode_trace_flush, 'tracing.test_mode.trace_flush')
        setting(:partial_flush, 'tracing.partial_flush.enabled')
        setting(:partial_flush_min_spans_threshold, 'tracing.partial_flush.min_spans_threshold')
        def self.new(test_mode, test_mode_trace_flush, partial_flush: false, partial_flush_min_spans_threshold: Flush::Partial::DEFAULT_MIN_SPANS_FOR_PARTIAL_FLUSH)
          # If context flush behavior is provided, use it instead.
          return test_mode_trace_flush if test_mode && test_mode_trace_flush

          if partial_flush
            Tracing::Flush::Partial.new(min_spans_before_partial_flush: partial_flush_min_spans_threshold)
          else
            Tracing::Flush::Finished.new
          end
        end
      end

      # TODO: Sampler should be a top-level component.
      # It is currently part of the Tracer initialization
      # process, but can take a variety of options (including
      # a fully custom instance) that makes the Tracer
      # initialization process complex.
      # def build_sampler(settings)
      #   if (sampler = settings.tracing.sampler)
      #     if settings.tracing.priority_sampling == false
      #       sampler
      #     else
      #       ensure_priority_sampling(sampler, settings)
      #     end
      #   elsif settings.tracing.priority_sampling == false
      #     Tracing::Sampling::RuleSampler.new(
      #       rate_limit: settings.tracing.sampling.rate_limit,
      #       default_sample_rate: settings.tracing.sampling.default_rate
      #     )
      #   else
      #     Tracing::Sampling::PrioritySampler.new(
      #       base_sampler: Tracing::Sampling::AllSampler.new,
      #       post_sampler: Tracing::Sampling::RuleSampler.new(
      #         rate_limit: settings.tracing.sampling.rate_limit,
      #         default_sample_rate: settings.tracing.sampling.default_rate
      #       )
      #     )
      #   end
      # end

      class Sampler
        extend Core::Dependency

        setting(:sampler, 'tracing.sampler')
        setting(:priority_sampling, 'tracing.priority_sampling')
        setting(:rate_limit, 'tracing.sampling.rate_limit')
        setting(:default_rate, 'tracing.sampling.default_rate')
        setting(:test_mode, 'tracing.test_mode.enabled')
        def self.new(sampler, priority_sampling, rate_limit, default_rate, test_mode)
          return build_test_mode_sampler if test_mode

          if sampler
            if priority_sampling == false
              sampler
            else
              ensure_priority_sampling(sampler, rate_limit, default_rate)
            end
          elsif priority_sampling == false
            Tracing::Sampling::RuleSampler.new(
              rate_limit: rate_limit,
              default_sample_rate: default_rate
            )
          else
            Tracing::Sampling::PrioritySampler.new(
              base_sampler: Tracing::Sampling::AllSampler.new,
              post_sampler: Tracing::Sampling::RuleSampler.new(
                rate_limit: rate_limit,
                default_sample_rate: default_rate
              )
            )
          end
        end

        def self.ensure_priority_sampling(sampler, rate_limit, default_rate)
          if sampler.is_a?(Tracing::Sampling::PrioritySampler)
            sampler
          else
            Tracing::Sampling::PrioritySampler.new(
              base_sampler: sampler,
              post_sampler: Tracing::Sampling::RuleSampler.new(
                rate_limit: rate_limit,
                default_sample_rate: default_rate
              )
            )
          end
        end

        def self.build_test_mode_sampler
          # Do not sample any spans for tests; all must be preserved.
          # Set priority sampler to ensure the agent doesn't drop any traces.
          Tracing::Sampling::PrioritySampler.new(
            base_sampler: Tracing::Sampling::AllSampler.new,
            post_sampler: Tracing::Sampling::AllSampler.new
          )
        end
      end


      # TODO: Writer should be a top-level component.
      # It is currently part of the Tracer initialization
      # process, but can take a variety of options (including
      # a fully custom instance) that makes the Tracer
      # initialization process complex.
      # def build_writer(settings, agent_settings)
      #   if (writer = settings.tracing.writer)
      #     return writer
      #   end
      #
      #   Tracing::Writer.new(agent_settings: agent_settings, **settings.tracing.writer_options)
      # end

      class Writer
        extend Core::Dependency

        component(:agent_settings)
        setting(:writer, 'tracing.writer')
        setting(:writer_options, 'tracing.writer_options')
        component(:sampler)
        setting(:test_mode, 'tracing.test_mode.enabled')
        setting(:test_mode_writer_options, 'tracing.test_mode.writer_options')

        class << self
          def new(agent_settings, writer, writer_options, sampler, test_mode, test_mode_writer_options)
            writer = if writer
                       writer
                     elsif test_mode
                       build_test_mode_writer(test_mode_writer_options, agent_settings)
                     else
                       Tracing::Writer.new(agent_settings: agent_settings, **writer_options)
                     end

            subscribe_to_writer_events!(writer, sampler, test_mode)
            writer
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

          # Create new lambda for writer callback,
          # capture the current sampler in the callback closure.
          def writer_update_priority_sampler_rates_callback(sampler)
            lambda do |_, responses|
              response = responses.last

              next unless response && !response.internal_error? && response.service_rates

              sampler.update(response.service_rates, decision: Tracing::Sampling::Ext::Decision::AGENT_RATE)
            end
          end

          def build_test_mode_writer(test_mode_writer_options, agent_settings)
            # Flush traces synchronously, to guarantee they are written.
            writer_options = test_mode_writer_options || {}
            Tracing::SyncWriter.new(agent_settings: agent_settings, **writer_options)
          end
        end

        WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK = lambda do |_, responses|
          Core::Diagnostics::EnvironmentLogger.log!(responses)
        end
      end

      # def build_span_sampler(settings)
      #   rules = Tracing::Sampling::Span::RuleParser.parse_json(settings.tracing.sampling.span_rules)
      #   Tracing::Sampling::Span::Sampler.new(rules || [])
      # end

      class SpanSampler
        extend Core::Dependency

        setting(:span_rules, 'tracing.sampling.span_rules')

        def self.new(span_rules)
          rules = Tracing::Sampling::Span::RuleParser.parse_json(span_rules)
          Tracing::Sampling::Span::Sampler.new(rules || [])
        end
      end

      def reconfigure(changes, settings = Datadog.configuration)
        settings.tracing.log_injection = env_to_bool(changes['DD_LOGS_INJECTION_ENABLED'], true) # DEV: Don't apply if can't parse it!
        log_injection_bonanza!(settings.tracing.log_injection) # Reconfigure a bunch of integrations

        # DEV: Currently lives in the global gem space, not tracing.
        settings.runtime_metrics.enabled = env_to_bool(changes['DD_RUNTIME_METRICS_ENABLED'], false)
        runtime_metrics.stop(true, close_metrics: false)
        @runtime_metrics = build_runtime_metrics_worker(settings)

        # DEV: There's only a global logger, not a specific trace logger
        settings.diagnostics.debug = changes['DD_TRACE_DEBUG_ENABLED']
        @logger = build_logger(settings)

        # DEV: Ugly
        settings.tracing.sampling.default_rate = env_to_float(changes['DD_TRACE_SAMPLE_RATE'], nil)
        settings.tracing.sampling.span_rules = changes['DD_SPAN_SAMPLING_RULES']
        # settings.tracing.sampling.rules = env_to_float(changes['DD_TRACE_SAMPLE_RULES'], nil) # Not implemented

        sampler = build_sampler(settings) # OK

        # DEV: Ugly
        writer = tracer.writer
        subscribe_to_writer_events!(writer, sampler, settings.tracing.test_mode.enabled)

        tracer.send(:sampler=, sampler) # OK

        # Post GA
        settings.tracing.enabled = env_to_bool(changes['DD_TRACE_ENABLED'], true)
        tracer.enabled = false

        # DD_SERVICE_MAPPING
        # Not implemented

        # DD_TRACE_HEADER_TAGS
        # Not implemented
        # "Comma-separated list of header names that are reported on the root span as tags. For example, `DD_TRACE_HEADER_TAGS="User-Agent:http.user_agent,Referer:http.referer,Content-Type:http.content_type,Etag:http.etag"`."
      end

      # Large one
      def log_injection_bonanza!(enabled)
        # patch! lograge
        # patch! semantic_logger
        # patch! activejob
        # patch! rails: Datadog::Tracing::Contrib::Rails::LogInjection#add_as_tagged_logging_logger

        # If already patched, then disable it on the fly
      end

      private

      # def build_tracer_tags(settings)
      #   settings.tags.dup.tap do |tags|
      #     tags[Core::Environment::Ext::TAG_ENV] = settings.env unless settings.env.nil?
      #     tags[Core::Environment::Ext::TAG_VERSION] = settings.version unless settings.version.nil?
      #   end
      # end
      #
      # def build_test_mode_trace_flush(settings)
      #   # If context flush behavior is provided, use it instead.
      #   settings.tracing.test_mode.trace_flush || build_trace_flush(settings)
      # end
      #
      # def build_test_mode_sampler
      #   # Do not sample any spans for tests; all must be preserved.
      #   # Set priority sampler to ensure the agent doesn't drop any traces.
      #   Tracing::Sampling::PrioritySampler.new(
      #     base_sampler: Tracing::Sampling::AllSampler.new,
      #     post_sampler: Tracing::Sampling::AllSampler.new
      #   )
      # end
      #
      # def build_test_mode_writer(settings, agent_settings)
      #   # Flush traces synchronously, to guarantee they are written.
      #   writer_options = settings.tracing.test_mode.writer_options || {}
      #   Tracing::SyncWriter.new(agent_settings: agent_settings, **writer_options)
      # end
    end
  end
end
