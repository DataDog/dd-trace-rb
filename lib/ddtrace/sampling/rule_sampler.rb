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

      attr_reader :rules, :rate_limiter, :priority_sampler

      def initialize(rules = [],
                     rate_limiter = Datadog::Sampling::UnlimitedLimiter.new,
                     priority_sampler = Datadog::AllSampler.new)
        @rules = rules
        @rate_limiter = rate_limiter
        @priority_sampler = priority_sampler
      end

      # /RuleSampler's components (it's rate limiter, for example) are
      # not be guaranteed to be size-effect free.
      # It is not possible to guarantee that a call to {#sample?} will
      # return the same result as a successive call to {#sample!} with the same span.
      #
      # Use {#sample!} instead
      def sample?(span)
        raise 'RuleSampler cannot be evaluated without side-effects'
      end

      def sample!(span)
        sample_span(span).tap do |sampled|
          span.sampled = sampled
        end
      end

      def_delegators :@priority_sampler, :update

      private

      def sample_span(span)
        sampled, sample_rate = @rules.find do |rule|
          result = rule.sample(span)
          break result if result
        end

        return @priority_sampler.sample!(span) if sampled.nil?

        set_rule_metrics(span, sample_rate)

        return false unless sampled

        rate_limiter.allow?(1).tap do
          set_limiter_metrics(span, rate_limiter.effective_rate)
        end
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
