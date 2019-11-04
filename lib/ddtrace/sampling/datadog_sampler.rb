module Datadog
  module Sampling
    class DatadogSampler
      def sample(span)
        # Check to see if there is a user defined rule that matches this span
        matching_rule = user_defined_rules.find do |rule|
          rule.matches(span)
        end

        # No rule matches this span, fallback to existing behavior
        unless matching_rule
          return existing_priority_sampler.sample(span)
        end

        # Check if the matching rule will sample the span
        unless matching_rule.sample(span)
          span.sampling_priority = AUTO_REJECT
          return false
        end

        # The span was sampled, verify we do not exceed our rate limit
        unless rate_limiter.is_allowed()
          span.sampling_priority = AUTO_REJECT
          return false
        end

        # Span should be sampled
        span.sampling_priority = AUTO_KEEP
        return true
      end
    end
  end
end