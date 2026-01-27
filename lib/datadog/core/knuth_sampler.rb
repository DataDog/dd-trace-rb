# frozen_string_literal: true

module Datadog
  module Core
    # Deterministic sampler using Knuth multiplicative hash algorithm.
    #
    # This sampler provides consistent sampling decisions based on an input value,
    # ensuring the same input always produces the same sampling decision for a given rate.
    #
    # The algorithm multiplies the input by a large prime (Knuth factor), takes modulo
    # to constrain to a fixed range, and compares against a threshold derived from the sample rate.
    #
    # @api private
    # @see https://en.wikipedia.org/wiki/Hash_function#Multiplicative_hashing
    class KnuthSampler
      # Maximum unsigned 64-bit integer for uniform distribution across 64-bit input space.
      UINT64_MAX = (1 << 64) - 1
      UINT64_MODULO = 1 << 64

      # Golden ratio constant for optimal distribution.
      # @see https://en.wikipedia.org/wiki/Hash_function#Fibonacci_hashing
      DEFAULT_KNUTH_FACTOR = 11400714819323198485

      attr_reader :rate

      # @param rate [Float] Sampling rate between +0.0+ and +1.0+ (inclusive).
      #   +0.0+ means no samples are kept; +1.0+ means all samples are kept.
      #   Invalid values fall back to +1.0+ (sample everything).
      # @param knuth_factor [Integer] Multiplicative constant for hashing.
      #   Different factors produce different sampling distributions.
      def initialize(rate = 1.0, knuth_factor: DEFAULT_KNUTH_FACTOR)
        @knuth_factor = knuth_factor

        rate = rate.to_f
        unless rate >= 0.0 && rate <= 1.0
          Datadog.logger.warn('Sample rate is not between 0.0 and 1.0, falling back to 1.0')
          rate = 1.0
        end

        @rate = rate
        @threshold = @rate * UINT64_MAX
      end

      # Determines if the given input should be sampled.
      #
      # This method is deterministic: the same input value always produces
      # the same result for a given sample rate and configuration.
      #
      # @param input [Integer] Value to determine sampling decision.
      #   Typically a trace ID or incrementing counter.
      # @return [Boolean] +true+ if input should be sampled, +false+ otherwise
      def sample?(input)
        ((input * @knuth_factor) % UINT64_MODULO) <= @threshold
      end
    end
  end
end
