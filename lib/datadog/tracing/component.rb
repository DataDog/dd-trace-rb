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
          span_sampler: build_span_sampler(settings),
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

          sampler.update(response.service_rates, decision: Tracing::Sampling::Ext::Decision::AGENT_RATE)
        end
      end

      def build_span_sampler(settings)
        rules = Tracing::Sampling::Span::RuleParser.parse_json(settings.tracing.sampling.span_rules)
        Tracing::Sampling::Span::Sampler.new(rules || [])
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
    end
  end
end
