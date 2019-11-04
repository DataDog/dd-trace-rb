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
