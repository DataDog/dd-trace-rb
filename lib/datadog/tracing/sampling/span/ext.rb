# frozen_string_literal: true

module Datadog
  module Tracing
    module Sampling
      module Span
        # Checks if a span conforms to a matching criteria.
        class Ext
          # Sampling decision method used to come to the sampling decision for this span
          TAG_MECHANISM = '_dd.span_sampling.mechanism'
          # Sampling rate applied to this span, if a rule applies
          TAG_RULE_RATE = '_dd.span_sampling.rule_rate'
          # Rate limit configured for this span, if a rule applies
          TAG_MAX_PER_SECOND = '_dd.span_sampling.max_per_second'

          # This span was sampled on account of a Span Sampling Rule
          # @see Datadog::Tracing::Sampling::Span::Rule
          MECHANISM_SPAN_SAMPLING_RATE = 8
        end
      end
    end
  end
end
