# frozen_string_literal: true

require_relative 'tracer'
require_relative 'configuration/agent_settings_resolver'
require_relative 'flush'
require_relative 'sync_writer'
require_relative 'sampling/span/rule_parser'
require_relative 'sampling/span/sampler'
require_relative 'diagnostics/environment_logger'

module Datadog
  module Tracing
    # Tracing component
    module Component
      # Methods that interact with component instance fields.
      module InstanceMethods
        # Hot-swaps with a new sampler.
        # This operation acquires the Components lock to ensure
        # there is no concurrent modification of the sampler.
        def reconfigure_live_sampler
          sampler = self.class.build_sampler(Datadog.configuration)
          Datadog.send(:safely_synchronize) { tracer.sampler.sampler = sampler }
        end
      end

      def build_tracer(settings, logger:)
        # If a custom tracer has been provided, use it instead.
        # Ignore all other options (they should already be configured.)
        tracer = settings.tracing.instance
        return tracer unless tracer.nil?

        agent_settings = Configuration::AgentSettingsResolver.call(settings, logger: logger)

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

        # The sampler instance is wrapped in a delegator,
        # so dynamic instrumentation can hot-swap it.
        # This prevents full tracer reinitialization on sampling changes.
        sampler_delegator = SamplerDelegatorComponent.new(sampler)

        subscribe_to_writer_events!(writer, sampler_delegator, settings.tracing.test_mode.enabled)

        Tracing::Tracer.new(
          default_service: settings.service,
          enabled: settings.tracing.enabled,
          trace_flush: trace_flush,
          sampler: sampler_delegator,
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
        elsif (rules = settings.tracing.sampling.rules)
          post_sampler = Tracing::Sampling::RuleSampler.parse(
            rules,
            settings.tracing.sampling.rate_limit,
            settings.tracing.sampling.default_rate
          )

          post_sampler ||= # Fallback RuleSampler in case `rules` parsing fails
            Tracing::Sampling::RuleSampler.new(
              rate_limit: settings.tracing.sampling.rate_limit,
              default_sample_rate: settings.tracing.sampling.default_rate
            )

          Tracing::Sampling::PrioritySampler.new(
            base_sampler: Tracing::Sampling::AllSampler.new,
            post_sampler: post_sampler
          )
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
      def build_writer(settings, agent_settings, options = settings.tracing.writer_options)
        if (writer = settings.tracing.writer)
          return writer
        end

        Tracing::Writer.new(agent_settings: agent_settings, **options)
      end

      def subscribe_to_writer_events!(writer, sampler_delegator, test_mode)
        return unless writer.respond_to?(:events) # Check if it's a custom, external writer

        writer.events.after_send.subscribe(&WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK)

        # DEV: We need to ignore priority sampling updates coming from the agent in test mode
        # because test mode wants to *unconditionally* sample all traces.
        #
        # This can cause trace metrics to be overestimated, but that's a trade-off we take
        # here to achieve 100% sampling rate.
        return if test_mode

        writer.events.after_send.subscribe(&writer_update_priority_sampler_rates_callback(sampler_delegator))
      end

      WRITER_RECORD_ENVIRONMENT_INFORMATION_CALLBACK = lambda do |_, responses|
        Tracing::Diagnostics::EnvironmentLogger.collect_and_log!(responses: responses)
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

      # Sampler wrapper component, to allow for hot-swapping
      # the sampler instance used by the tracer.
      # Swapping samplers happens during Dynamic Configuration.
      class SamplerDelegatorComponent
        attr_accessor :sampler

        def initialize(sampler)
          @sampler = sampler
        end

        def sample!(trace)
          @sampler.sample!(trace)
        end

        def update(*args, **kwargs)
          return unless @sampler.respond_to?(:update)

          @sampler.update(*args, **kwargs)
        end
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
        writer_options = settings.tracing.test_mode.writer_options || {}

        return build_writer(settings, agent_settings, writer_options) if settings.tracing.test_mode.async

        # Flush traces synchronously, to guarantee they are written.
        Tracing::SyncWriter.new(agent_settings: agent_settings, **writer_options)
      end
    end
  end
end
