# SCRATCHPAD TODO: Remove this file

Datadog.configure do |c|
  c.tracer sampler: Datadog::Sampling::RuleSampler.new(
    [
      Datadog::Sampling::SimpleRule.new(name: 'operation.name', sample_rate: 0.9),
      Datadog::Sampling::SimpleRule.new(service: 'service-1', sample_rate: 0.9),
      Datadog::Sampling::SimpleRule.new(sample_rate: 0.7) { |span| span.name != 'important.operation' },
      Datadog::Sampling::SimpleRule.new(sample_rate: 1.0),
    ],
    Datadog::Sampling::TokenBucket.new(1),
    Datadog::PrioritySampler.new(
      post_sampler: Datadog::RateByServiceSampler.new(
        1.0,
        env: proc { Datadog.tracer.tags[:env] } # TODO how do I provide `tracer.tags`? Seems like a circular reference here.
      )
    )
  )
end

# TEST SNIPPET
# require 'ddtrace'; require 'ddtrace/sampling/rule_sampler'; require 'ddtrace/sampling/rule'; require 'ddtrace/sampling/token_bucket'; Datadog.configure { |c| c.tracer sampler: Datadog::Sampling::RuleSampler.new([Datadog::Sampling::SimpleRule.new(sample_rate: 0.9)], Datadog::Sampling::TokenBucket.new(1)) }; Datadog.tracer.trace('name') { |span| pp span.context; nil }
