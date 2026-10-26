# frozen_string_literal: true

require_relative "refillable_bucket"

module Datadog
  module Core
    # Token bucket that permits consumption below zero. The deficit refills over
    # time at +rate+.
    class BorrowingTokenBucket
      include RefillableBucket

      # Initializes the balance at +max_tokens+, permitting the balance to go
      # below zero thereafter.
      #
      # @param rate [Numeric] refill rate, in tokens per second. A zero rate
      #   adds zero tokens per second, so the balance only decreases; a
      #   negative rate raises +ArgumentError+.
      # @param max_tokens [Numeric] ceiling the balance refills toward
      # @raise [ArgumentError] when rate or max_tokens is negative, or when
      #   either is not a number
      def initialize(rate, max_tokens: rate)
        super(rate, max_tokens)

        raise ArgumentError, "rate must not be negative: #{rate}" if rate < 0
        raise ArgumentError, "max_tokens must not be negative: #{max_tokens}" if max_tokens < 0
      end

      # @return [Boolean] whether the balance is currently positive
      def available?
        refill
        available_tokens > 0
      end

      # Removes +size+ tokens, driving the balance negative when the bucket is
      # short.
      #
      # @param size [Numeric] tokens to remove
      # @return [void]
      # @raise [ArgumentError] when size is negative or is not a number
      def consume(size: 1)
        raise ArgumentError, "size must be a number: #{size}" unless size.is_a?(Numeric)
        raise ArgumentError, "size must not be negative: #{size}" if size < 0

        refill
        @tokens = available_tokens - size
        nil
      end

      # Removes one token when the balance is positive after a refill, so a
      # check-and-consume reads the clock and runs the refill arithmetic once.
      #
      # @return [Boolean] whether a token was consumed
      def try_consume
        refill
        return false unless available_tokens > 0

        @tokens = available_tokens - 1
        true
      end
    end
  end
end
