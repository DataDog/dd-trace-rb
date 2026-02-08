# frozen_string_literal: true

require_relative '../core/knuth_sampler'

module Datadog
  module AppSec
    # Sampler that uses an internal counter to make deterministic sampling decisions.
    #
    # Each call to {#sample?} increments the counter and uses it as input to
    # the underlying Knuth multiplicative hash algorithm.
    #
    # @api private
    class CounterSampler
      def initialize(rate = 1.0)
        @sampler = Core::KnuthSampler.new(rate)
        @counter = 0
      end

      def sample?
        @counter += 1
        @sampler.sample?(@counter)
      end
    end
  end
end
