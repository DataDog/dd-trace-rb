# typed: true

require_relative 'ext'
require_relative 'all_sampler'
require_relative 'rate_sampler'
require_relative 'rate_by_service_sampler'

module Datadog
  module Tracing
    module Sampling
      # {Datadog::Tracing::Sampling::PrioritySampler}
      # @public_api
      class PrioritySampler
        # NOTE: We do not advise using a pre-sampler. It can save resources,
        # but pre-sampling at rates < 100% may result in partial traces, unless
        # the pre-sampler knows exactly how to drop a span without dropping its ancestors.
        #
        # Additionally, as service metrics are calculated in the Datadog Agent,
        # the service's throughput will be underestimated.
        attr_reader :pre_sampler, :priority_sampler

        def initialize(opts = {})
          @pre_sampler = opts[:base_sampler] || AllSampler.new
          @priority_sampler = opts[:post_sampler] || RateByServiceSampler.new
        end

        def sample?(trace)
          @pre_sampler.sample?(trace)
        end

        def sample!(trace)
          # If pre-sampling is configured, do it first. (By default, this will sample at 100%.)
          # NOTE: Pre-sampling at rates < 100% may result in partial traces; not recommended.
          trace.sampled = pre_sample?(trace) ? @pre_sampler.sample!(trace) : true

          if trace.sampled?
            # If priority sampling has already been applied upstream, use that value.
            return true if priority_assigned?(trace)

            # Check with post sampler how we set the priority.
            sample = priority_sample!(trace)

            # Check if post sampler has already assigned a priority.
            return true if priority_assigned?(trace)

            # If not, use agent priority values.
            priority = sample ? Sampling::Ext::Priority::AUTO_KEEP : Sampling::Ext::Priority::AUTO_REJECT
            assign_priority!(trace, priority)
          else
            # If discarded by pre-sampling, set "reject" priority, so other
            # services for the same trace don't sample needlessly.
            assign_priority!(trace, Sampling::Ext::Priority::AUTO_REJECT)
          end

          trace.sampled?
        end

        # (see Datadog::Tracing::Sampling::RateByServiceSampler#update)
        def update(rate_by_service)
          @priority_sampler.update(rate_by_service)
        end

        private

        def pre_sample?(trace)
          case @pre_sampler
          when RateSampler
            @pre_sampler.sample_rate < 1.0
          when RateByServiceSampler
            @pre_sampler.sample_rate(trace) < 1.0
          else
            true
          end
        end

        def priority_assigned?(trace)
          !trace.sampling_priority.nil?
        end

        def priority_sample!(trace)
          preserving_sampling(trace) do
            @priority_sampler.sample!(trace)
          end
        end

        # Ensures the trace is always propagated to the writer and that
        # the sample rate metric represents the true client-side sampling.
        def preserving_sampling(trace)
          pre_sample_rate_metric = trace.sample_rate

          yield.tap do
            # NOTE: We'll want to leave `trace.sampled = true` here; all spans for priority sampling must
            #       be sent to the agent. Otherwise metrics for traces will not be accurate, since the
            #       agent will have an incomplete dataset.
            #
            #       We also ensure that the agent knows we that our `post_sampler` is not performing true sampling,
            #       to avoid erroneous metric upscaling.
            trace.sampled = true

            # Restore true sampling metric, as only the @pre_sampler can reject traces.
            # otherwise if @pre_sampler is not enabled, sending this metric would be misleading.
            trace.sample_rate = pre_sample_rate_metric || nil
          end
        end

        def assign_priority!(trace, priority)
          trace.sampling_priority = priority
        end
      end
    end
  end
end
