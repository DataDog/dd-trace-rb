module Datadog
  module Ext
    module Sampling
      # If rule sampling is applied to a span, set this metric the sample rate configured for that rule.
      # This should be done regardless of sampling outcome.
      RULE_SAMPLE_RATE = '_dd.rule_psr'.freeze

      # If rate limiting is checked on a span, set this metric the effective rate limiting rate applied.
      # This should be done regardless of rate limiting outcome.
      RATE_LIMITER_RATE = '_dd.limit_psr'.freeze
    end
  end
end
