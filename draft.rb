begin

  true
end

global_rate_limiter = RateLimiter.new(100) # hit/s

local_rate_limiter = RateLimiter.new(50)

sampling = [
  Rule.new(service, name, 0.5),
  Rule.new(service: service, name: name, sampling_rage: 0.5),
  Rule.new(name, 0.4),
  Rule.new(service, 1),
  Rule.new(name) { |service, _name| service == '???' ? 0.5 : 0 },
  Rule.new(service) { |_service, name| name == '???' ? 0.5 : 0 },
  Rule.new { |service, name| service == 'my-service' && name != 'skip' ? 0.5 * local_rate_limiter.sample : 0 },
  Rule.new do |service, name|
    case service
    when 'service_1'
      local_rate_limiter.sample
    else
      service == 'my-service' && name != 'skip' ? 0.5 * local_rate_limiter.sample : 0
    end
  end,
  Rule.new(service, name) { _, _ }, # Error, we'll never call the block, as we have all matching conditions!
  Rule.new { |span| ... }, # How about this?
  Rule.new(0.9), # catch all
  Rule.new(service, 1), # no-op, as it comes after a catch all, we should probably log an alert
  Rule.new(CurrentImplemention), # Implicit default fallback, that does the same thing as today, probably not needed when a catch all rule is present
]

class TokenBucket
  # TODO:
end

class Rule
  # @abstract
  # @!method sample
  # @param span
  # @return [Boolean, Float] sampling decision and sampling rate, or +nil+ if this rule does not apply
end

class SimpleRule < Rule
  MATCH_ALL = Proc.new { |_obj| true }

  attr_reader :service, :name, :sampling_rate

  #
  # (e.g. \String, \Regexp, \Proc)
  #
  # @param service Matcher for case equality (===) with the service name, defaults to always match
  # @param name Matcher for case equality (===) with the span name, defaults to always match
  # @param sampling_rate
  def initialize(service: MATCH_ALL, name: MATCH_ALL, sampling_rate:)
    @sampler = Datadog::RateSampler.new(sampling_rate)
  end

  def sample(span)
    [@sampler.sample?(span), sampling_rate] if match?(span)
  end

  private

  def match?(span)
    service === span.service && name === span.name
  end
end

class CustomRule < Rule
  attr_reader :block

  def initialize(&block)
  end

  def sample(span)
    block.(span.service, span.name)
  end
end

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


_dd.agent_psr - agent service priority rate
the rate limit returned by the agent
only needs to be added if no rules match and we fallback to existing sampling behavior
although, can be added even if they aren 't using the new sampler
_dd.rule_psr - sample rate configured for the matching rule
If a rule matches, add this tag with the sample rate configured for that rule
Set this regardless of p0 or p1
_dd.limit_psr - rate limiter effective sample rate
should be set whenever the rate limiter is checked (any p1' s from matching rule)
should be set whether rate limiter allows the span or not


sampler = Datadog::RateSampler.new(0.5) # sample 50% of the traces

Datadog.configure do |c|
  c.tracer sampler: sampler
end
