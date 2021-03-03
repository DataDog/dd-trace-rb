require 'ddtrace/sampler'
require 'ddtrace/sampling/rule_sampler'

module Datadog
  module Sampling
    # Defines behaviors for priority sampling
    module PrioritySampling
      module_function

      def new_sampler(base_sampler = nil)
        return base_sampler if base_sampler.is_a?(Datadog::PrioritySampler)

        PrioritySampler.new(
          base_sampler: base_sampler || Datadog::AllSampler.new,
          post_sampler: Sampling::RuleSampler.new
        )
      end

      def activate!(priority_sampler, trace_writer)
        raise ArgumentError, 'Priority sampler and trace writer are required' if priority_sampler.nil? || trace_writer.nil?

        # Subscribe to #flush_completed
        trace_writer.flush_completed.subscribe(:priority_sampling) do |responses|
          responses.each do |response|
            if response.respond_to?(:service_rates) && !response.service_rates.nil?
              priority_sampler.update(response.service_rates)
            end
          end
        end
      end

      def deactivate!(trace_writer)
        raise ArgumentError, 'Trace writer is required' if trace_writer.nil?

        # Unsubscribe from #flush_completed
        trace_writer.flush_completed.unsubscribe(:priority_sampling)
      end
    end
  end
end
