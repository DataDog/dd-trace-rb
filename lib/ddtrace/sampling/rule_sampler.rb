require 'forwardable'

require 'ddtrace/ext/priority'

require 'ddtrace/ext/sampling'
require 'ddtrace/sampler'
require 'ddtrace/sampling/token_bucket'

module Datadog
  module Sampling
    # TODO: Write class documentation
    # RuleSampler
    class RuleSampler
      extend Forwardable

      attr_reader :rules, :rate_limiter, :default_sampler

      def initialize(rules = [],
                     rate_limiter = Datadog::Sampling::UnlimitedLimiter.new,
                     default_sampler = Datadog::AllSampler.new)
        @rules = rules
        @rate_limiter = rate_limiter
        @default_sampler = default_sampler
      end

      # /RuleSampler's components (it's rate limiter, for example) are
      # not be guaranteed to be size-effect free.
      # It is not possible to guarantee that a call to {#sample?} will
      # return the same result as a successive call to {#sample!} with the same span.
      #
      # Use {#sample!} instead
      def sample?(_span)
        raise 'RuleSampler cannot be evaluated without side-effects'
      end

      def sample!(span)
        sampled = sample_span(span) { |s| @default_sampler.sample!(s) }

        sampled.tap do
          span.sampled = true
          span.context.sampling_priority = sampled ? Datadog::Ext::Priority::AUTO_KEEP : Datadog::Ext::Priority::AUTO_REJECT
        end
      end

      def_delegators :@default_sampler, :update

      private

      def sample_span(span)
        rule = @rules.find { |r| r.match?(span) }

        return yield(span) if rule.nil?

        sampled = rule.sample?(span)
        sample_rate = rule.sample_rate(span)

        set_rule_metrics(span, sample_rate)

        return false unless sampled

        rate_limiter.allow?(1).tap do
          set_limiter_metrics(span, rate_limiter.effective_rate)
        end
      rescue StandardError => e
        Datadog::Tracer.log.error("Rule sampling failed. Cause: #{e.message} Source: #{e.backtrace.first}")
        yield(span)
      end

      def set_rule_metrics(span, sample_rate)
        span.set_metric(Ext::Sampling::RULE_SAMPLE_RATE, sample_rate)
      end

      def set_limiter_metrics(span, limiter_rate)
        span.set_metric(Ext::Sampling::RATE_LIMITER_RATE, limiter_rate)
      end
    end
  end
end
