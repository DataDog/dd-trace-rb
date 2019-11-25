module Datadog
  module Ext
    module Sampling
      # TODO Comments have to be polished

      # If a rule matches, add this tag with the sample rate configured for that rule
      # Set this regardless of p0 or p1
      RULE_SAMPLE_RATE = '_dd.rule_psr'.freeze

      # should be set whenever the rate limiter is checked (any p1' s from matching rule)
      # should be set whether rate limiter allows the span or not
      RATE_LIMITER_RATE = '_dd.limit_psr'.freeze

      # TODO move this metric to future PR
      # agent service priority rate
      # the rate limit returned by the agent
      # only needs to be added if no rules match and we fallback to existing sampling behavior
      # although, can be added even if they aren 't using the new sampler
      AGENT_SERVICE_PRIORITY_RATE = '_dd.agent_psr'.freeze
    end
  end
end
