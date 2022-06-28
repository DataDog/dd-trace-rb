# typed: true

require 'datadog/core'

require 'datadog/tracing/sampling/sampler'
require 'datadog/tracing/span'

module Datadog
  module Tracing
    module Sampling
      # {Datadog:::Tracing::Sampling::RateSampler} is based on a sample rate.
      # @public_api
      class RateSampler < Sampler
        KNUTH_FACTOR = 1111111111111111111

        # Initialize a {Datadog:::Tracing::Sampling::RateSampler}.
        # This sampler keeps a random subset of the traces. Its main purpose is to
        # reduce the instrumentation footprint.
        #
        # * +sample_rate+: the sample rate as a {Float} between 0.0 and 1.0. 0.0
        #   means that no trace will be sampled; 1.0 means that all traces will be
        #   sampled.
        #
        # DEV-2.0: Allow for `sample_rate` zero (drop all) to be allowed. This eases
        # DEV-2.0: usage for many consumers of the {RateSampler} class.
        def initialize(sample_rate = 1.0)
          super()

          unless sample_rate > 0.0 && sample_rate <= 1.0
            Datadog.logger.error('sample rate is not between 0 and 1, disabling the sampler')
            sample_rate = 1.0
          end

          self.sample_rate = sample_rate
        end

        def sample_rate(*_)
          @sample_rate
        end

        def sample_rate=(sample_rate)
          @sample_rate = sample_rate
          @sampling_id_threshold = sample_rate * Tracing::Span::EXTERNAL_MAX_ID
        end

        def sample?(trace)
          ((trace.id * KNUTH_FACTOR) % Tracing::Span::EXTERNAL_MAX_ID) <= @sampling_id_threshold
        end

        def sample!(trace)
          sampled = trace.sampled = sample?(trace)
          trace.sample_rate = @sample_rate if sampled
          sampled
        end
      end
    end
  end
end
