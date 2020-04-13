require 'ddtrace/sampler'
require 'ddtrace/sampling/rule_sampler'

module Datadog
  module Sampling
    # Defines behaviors for priority sampling
    module PrioritySampling
      module_function

      def activate!(options = {})
        tracer = options.fetch(:tracer) { Datadog.tracer }
        trace_writer = options.fetch(:trace_writer) { Datadog.trace_writer }

        unless tracer.sampler.is_a?(PrioritySampler)
          # Build a priority sampler
          sampler = PrioritySampler.new(
            base_sampler: tracer.sampler,
            post_sampler: Sampling::RuleSampler.new
          )

          # Replace sampler on the tracer
          tracer.configure(sampler: sampler)
        end

        # Subscribe to #flush_completed
        trace_writer.flush_completed.subscribe(:priority_sampling) do |responses|
          responses.each do |response|
            if response.respond_to?(:service_rates) && !response.service_rates.nil?
              tracer.sampler.update(response.service_rates)
            end
          end
        end
      end

      def deactivate!(options = {})
        tracer = options.fetch(:tracer) { Datadog.tracer }
        trace_writer = options.fetch(:trace_writer) { Datadog.trace_writer }

        # Replace sampler on the tracer
        if tracer.sampler.is_a?(PrioritySampler)
          sampler = options[:sampler] || Sampling::RuleSampler.new
          tracer.configure(sampler: sampler)
        end

        # Unsubscribe from #flush_completed
        trace_writer.flush_completed.unsubscribe(:priority_sampling)
      end
    end
  end
end
