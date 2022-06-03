# frozen_string_literal: true

module Datadog
  module Tracing
    module Sampling
      module Span
        # Checks if a span conforms to a matching criteria.
        class Ext
          # Sampling decision method used to come to the sampling decision for this span
          TAG_MECHANISM = '_dd.span_sampling.mechanism'
          # Sampling rate applied to this span
          TAG_RULE_RATE = '_dd.span_sampling.rule_rate'
          # Effective sampling ratio for the rate limiter configured for this span
          # @see Datadog::Tracing::Sampling::TokenBucket#effective_rate
          TAG_LIMIT_RATE = '_dd.span_sampling.limit_rate'

          # This span was sampled on account of a Span Sampling Rule
          # @see Datadog::Tracing::Sampling::Span::Rule
          MECHANISM_SPAN_SAMPLING_RATE = 8
        end
      end
    end
  end
end
