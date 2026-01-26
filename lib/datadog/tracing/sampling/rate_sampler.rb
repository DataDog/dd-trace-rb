# frozen_string_literal: true

require_relative 'sampler'
require_relative '../../core/knuth_sampler'

module Datadog
  module Tracing
    module Sampling
      # {Datadog::Tracing::Sampling::RateSampler} is based on a sample rate.
      class RateSampler < Sampler
        KNUTH_FACTOR = 1111111111111111111

        # Initialize a {Datadog::Tracing::Sampling::RateSampler}.
        # This sampler keeps a random subset of the traces. Its main purpose is to
        # reduce the instrumentation footprint.
        #
        # @param sample_rate [Numeric] the sample rate between 0.0 and 1.0, inclusive.
        #   0.0 means that no trace will be sampled; 1.0 means that all traces will be sampled.
        def initialize(sample_rate = 1.0, decision: nil)
          super()
          @sampler = Core::KnuthSampler.new(sample_rate, knuth_factor: KNUTH_FACTOR)
          @decision = decision
        end

        def sample_rate(*_)
          @sampler.rate
        end

        def sample_rate=(sample_rate)
          @sampler.rate = sample_rate
        end

        def sample?(trace)
          @sampler.sample?(trace.id)
        end

        def sample!(trace)
          return false unless sample?(trace)

          trace.sample_rate = sample_rate
          trace.set_tag(Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER, @decision) if @decision

          true
        end
      end
    end
  end
end
