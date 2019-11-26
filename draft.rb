# rubocop:disable all
# SCRATCHPAD TODO: Remove this file before merging

# Tracing without limits
require 'ddtrace'

Datadog.configure do |c|
  c.tracer sampler: Datadog::PrioritySampler.new(post_sampler: Datadog::Sampling::RuleSampler.new), debug: true
end;

Datadog.tracer.trace('operation.name') {}

# Rule-based tracing
Datadog.configure do |c|
  c.tracer sampler: Datadog::Sampling::RuleSampler.new(
    [
      Datadog::Sampling::SimpleRule.new(name: 'operation.name', sample_rate: 0.9),
      Datadog::Sampling::SimpleRule.new(service: 'service-1', sample_rate: 0.9),
      Datadog::Sampling::SimpleRule.new(sample_rate: 0.7) { |span| span.name != 'important.operation' },
      Datadog::Sampling::SimpleRule.new(sample_rate: 1.0)
    ],
    default_sampler: Datadog::RateSampler.new(1.0),
    rate_limiter: Datadog::Sampling::TokenBucket.new(1000),
  )
end

# TEST SNIPPET
# require 'ddtrace'; require 'ddtrace/sampling/rule_sampler'; require 'ddtrace/sampling/rule'; require 'ddtrace/sampling/token_bucket'; Datadog.configure { |c| c.tracer sampler: Datadog::Sampling::RuleSampler.new([Datadog::Sampling::SimpleRule.new(sample_rate: 0.9)], Datadog::Sampling::TokenBucket.new(1)) }; Datadog.tracer.trace('name') { |span| pp span.context; nil }
