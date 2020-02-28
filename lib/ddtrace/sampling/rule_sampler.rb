require 'forwardable'

require 'ddtrace/ext/priority'

require 'ddtrace/ext/sampling'
require 'ddtrace/sampler'
require 'ddtrace/sampling/rate_limiter'

module Datadog
  module Sampling
    # Span {Sampler} that applies a set of {Rule}s to decide
    # on sampling outcome. Then, a rate limiter is applied.
    #
    # If a span does not conform to any rules, a default
    # sampling strategy is applied.
    class RuleSampler
      extend Forwardable

      AGENT_RATE_METRIC_KEY = '_dd.agent_psr'.freeze

      attr_reader :rules, :rate_limiter, :default_sampler

      # @param rules [Array<Rule>] ordered list of rules to be applied to a span
      # @param rate_limit [Float] number of traces per second, defaults to +100+
      # @param rate_limiter [RateLimiter] limiter applied after rule matching
      # @param default_sample_rate [Float] fallback sample rate when no rules apply to a span,
      #   between +[0,1]+, defaults to +1+
      # @param default_sampler [Sample] fallback strategy when no rules apply to a span
      def initialize(rules = [],
                     rate_limit: Datadog.configuration.sampling.rate_limit,
                     rate_limiter: nil,
                     default_sample_rate: Datadog.configuration.sampling.default_rate,
                     default_sampler: nil)

        @rules = rules

        @rate_limiter = if rate_limiter
                          rate_limiter
                        elsif rate_limit
                          Datadog::Sampling::TokenBucket.new(rate_limit)
                        else
                          Datadog::Sampling::UnlimitedLimiter.new
                        end

        @default_sampler = if default_sampler
                             default_sampler
                           elsif default_sample_rate
                             # We want to allow 0.0 to drop all traces, but \RateSampler
                             # considers 0.0 an invalid rate and falls back to 100% sampling.
                             #
                             # We address that here by not setting the rate in the constructor,
                             # but using the setter method.
                             #
                             # We don't want to make this change directly to \RateSampler
                             # because it breaks its current contract to existing users.
                             Datadog::RateSampler.new.tap { |s| s.sample_rate = default_sample_rate }
                           else
                             RateByServiceSampler.new(1.0, env: -> { Datadog.tracer.tags[:env] })
                           end
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
        sampled = sample_span(span) do |s|
          @default_sampler.sample!(s).tap do
            # We want to make sure the span is tagged with the agent-derived
            # service rate. Retrieve this from the rate by service sampler.
            # Only do this if it was set by a RateByServiceSampler.
            if @default_sampler.is_a?(RateByServiceSampler)
              s.set_metric(AGENT_RATE_METRIC_KEY, @default_sampler.sample_rate(span))
            end
          end
        end

        sampled.tap do
          span.sampled = sampled
        end
      end

      def update(*args)
        return false unless @default_sampler.respond_to?(:update)
        @default_sampler.update(*args)
      end

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
        Datadog::Logger.log.error("Rule sampling failed. Cause: #{e.message} Source: #{e.backtrace.first}")
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
