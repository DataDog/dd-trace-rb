require 'ddtrace/ext/priority'

require 'ddtrace/ext/sampling'
require 'ddtrace/sampler'

module Datadog
  module Sampling
    # TODO:
    class RuleSampler
      extend Forwardable

      attr_reader :rules, :rate_limiter, :priority_sampler

      def initialize(rules, rate_limiter, priority_sampler = Datadog::RateByServiceSampler.new)
        @rules = rules
        @rate_limiter = rate_limiter
        @priority_sampler = priority_sampler
      end

      def sample?(span)
        sampled, _ = sample_span(span) { |s| return @priority_sampler.sample?(s) }
        sampled
      end

      def sample!(span)
        sampled, sample_rate = sample_span(span) { |s| return @priority_sampler.sample!(s) }

        # Set metrics regardless of sampling outcome
        set_metrics(span, sample_rate, rate_limiter.effective_rate)

        span.sampled = sampled
        sampled
      end

      def_delegators :@priority_sampler, :update

      private

      def sample_span(span)
        sampled, sample_rate = @rules.find do |rule|
          result = rule.sample(span)
          break result if result
        end

        return yield(span) if sampled.nil?

        [sampled && rate_limiter.allow?(1), sample_rate]
      end

      def set_metrics(span, sample_rate, limiter_rate)
        span.set_metric(Ext::Sampling::RULE_SAMPLE_RATE, sample_rate)
        span.set_metric(Ext::Sampling::RATE_LIMITER_RATE, limiter_rate)
      end
    end
  end
end