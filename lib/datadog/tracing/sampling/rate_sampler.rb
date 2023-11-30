require_relative 'sampler'
require_relative '../utils'

module Datadog
  module Tracing
    module Sampling
      # {Datadog::Tracing::Sampling::RateSampler} is based on a sample rate.
      # @public_api
      class RateSampler < Sampler
        KNUTH_FACTOR = 1111111111111111111

        # Initialize a {Datadog::Tracing::Sampling::RateSampler}.
        # This sampler keeps a random subset of the traces. Its main purpose is to
        # reduce the instrumentation footprint.
        #
        # @param sample_rate [Numeric] the sample rate between 0.0 and 1.0, inclusive.
        #   0.0 means that no trace will be sampled; 1.0 means that all traces will be  sampled.
        def initialize(sample_rate = 1.0, decision: nil)
          super()

          unless sample_rate >= 0.0 && sample_rate <= 1.0
            Datadog.logger.error('sample rate is not between 0 and 1, falling back to 1')
            sample_rate = 1.0
          end

          self.sample_rate = sample_rate

          @decision = decision
        end

        def sample_rate(*_)
          @sample_rate
        end

        def sample_rate=(sample_rate)
          @sample_rate = sample_rate
          @sampling_id_threshold = sample_rate * Tracing::Utils::EXTERNAL_MAX_ID
        end

        def sample?(trace)
          ((trace.id * KNUTH_FACTOR) % Tracing::Utils::EXTERNAL_MAX_ID) <= @sampling_id_threshold
        end

        def sample!(trace)
          sampled = trace.sampled = sample?(trace)

          return false unless sampled

          trace.sample_rate = @sample_rate
          trace.set_tag(Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER, @decision) if @decision

          true
        end
      end
    end
  end
end
