# frozen_string_literal: true

require_relative "utils/time"

module Datadog
  module Core
    # Token-bucket balance shared by rate limiter classes: the balance
    # refills at +rate+ tokens per second toward +max_tokens+, and including
    # classes define the admission policy on top of it.
    module RefillableBucket
      # Initializes the bucket: the balance starts at +max_tokens+ and refills
      # at +rate+ tokens per second.
      #
      # @param rate [Numeric] refill rate, in tokens per second
      # @param max_tokens [Numeric] ceiling the balance refills toward
      # @raise [ArgumentError] when rate or max_tokens is not a number
      def initialize(rate, max_tokens)
        raise ArgumentError, "rate must be a number: #{rate}" unless rate.is_a?(Numeric)
        raise ArgumentError, "max_tokens must be a number: #{max_tokens}" unless max_tokens.is_a?(Numeric)

        super()

        @rate = rate
        @max_tokens = max_tokens
        @tokens = max_tokens
        @last_refill = Core::Utils::Time.get_time

        nil # standard:disable Lint/Void
      end

      # @return [Numeric] refill rate, in tokens per second
      attr_reader :rate

      # @return [Numeric] ceiling the balance refills toward
      attr_reader :max_tokens

      # Monotonic time of the last refill, in seconds, read from the process
      # monotonic clock.
      #
      # @return [Numeric]
      attr_reader :last_refill

      # @return [Numeric] the token balance as of the last refill; reads
      #   between refills return a stale balance
      def available_tokens
        @tokens
      end

      private

      # Adds +rate+ times the seconds elapsed since the last refill to the
      # balance, capping it at +max_tokens+.
      # @return [void]
      def refill
        now = Core::Utils::Time.get_time
        refill_tokens(rate * (now - last_refill))
        @last_refill = now

        nil
      end

      # Adds +size+ tokens to the balance, capping it at +max_tokens+.
      # @param size [Numeric] tokens to add
      # @return [void]
      def refill_tokens(size)
        @tokens = available_tokens + size
        @tokens = max_tokens if available_tokens > max_tokens

        nil
      end
    end
  end
end
