require 'ddtrace/sampler'
require 'ddtrace/sampling/rule_sampler'

module Datadog
  module Sampling
    module PrioritySampling
      module_function

      def activate!(options = {})
        tracer = options.fetch(:tracer, Datadog.tracer)
        writer = options.fetch(:writer, Datadog.configuration.workers.trace_writer)

        if !tracer.sampler.is_a?(PrioritySampler)
          # Build a priority sampler
          sampler = PrioritySampler.new(
                      base_sampler: tracer.sampler,
                      post_sampler: Sampling::RuleSampler.new
                    )

          # Replace sampler on the tracer
          tracer.configure(sampler: sampler)
        end

        # Subscribe to #flush_completed
        writer.flush_completed.subscribe(:priority_sampling) do |response|
          tracer.sampler.update(response.service_rates) unless response.service_rates.nil?
        end
      end

      def deactivate!(options = {})
        tracer = options.fetch(:tracer, Datadog.tracer)
        writer = options.fetch(:writer, Datadog.configuration.workers.trace_writer)

        # Replace sampler on the tracer
        if tracer.sampler.is_a?(PrioritySampler)
          sampler = options.fetch(:sampler, Sampling::RuleSampler.new)
          tracer.configure(sampler: sampler)
        end

        # Unsubscribe from #flush_completed
        writer.flush_completed.unsubscribe(:priority_sampling)
      end
    end
  end
end
