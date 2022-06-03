# frozen_string_literal: true

require 'datadog/tracing/sampling/span/ext'

module Datadog
  module Tracing
    module Sampling
      module Span
        # Span sampling rule that applies a sampling rate if the span
        # matches the provided {Matcher}.
        # Additionally, a rate limiter is also applied.
        #
        # If a span does not conform to the matcher, no changes are made.
        class Rule
          # Creates a new span sampling rule.
          #
          # @param [Sampling::Span::Matcher] matcher whether this rule applies to a specific span
          # @param [Float] sampling_rate span sampling ratio, between 0.0 (0%) and 1.0 (100%).
          # @param [Numeric] rate_limit maximum number of spans sampled per second. Negative numbers mean unlimited spans.
          def initialize(matcher, sampling_rate, rate_limit)
            @matcher = matcher
            @sampling_rate = sampling_rate
            @rate_limit = rate_limit

            @sampler = Sampling::RateSampler.new
            @sampler.sample_rate = sampling_rate
            @rate_limiter = Sampling::TokenBucket.new(rate_limit)
          end

          # This method should only be invoked for spans that are part
          # of a trace that has been dropped by trace-level sampling.
          # Invoking it for other spans will cause incorrect sampling
          # metrics to be reported by the Datadog App.
          #
          # Returns `true` if the provided span is sampled.
          # If the span is dropped due to sampling rate or rate limiting,
          # it returns `false`.
          #
          # Returns `nil` if the span did not meet the matching criteria by the
          # provided matcher.
          #
          # This method modifies the `span` if it matches the provided matcher.
          #
          # @param [Datadog::Tracing::SpanOperation] span_op span to be sampled
          # @return [Boolean] should this span be sampled?
          # @return [nil] span did not satisfy the matcher, no changes are made to the span
          def sample!(span_op)
            return nil unless @matcher.match?(span_op)

            if @sampler.sample?(span_op) && @rate_limiter.allow?(1)
              span_op.set_metric(Span::Ext::TAG_MECHANISM, Span::Ext::MECHANISM_SPAN_SAMPLING_RATE)
              span_op.set_metric(Span::Ext::TAG_RULE_RATE, @sampling_rate)
              span_op.set_metric(Span::Ext::TAG_LIMIT_RATE, @rate_limiter.effective_rate)
              true
            else
              false
            end
          end
        end
      end
    end
  end
end
