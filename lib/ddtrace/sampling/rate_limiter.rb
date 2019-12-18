require 'ddtrace/utils/time'

module Datadog
  module Sampling
    # Checks for rate limiting on a resource.
    class RateLimiter
      # Checks if resource of specified size can be
      # conforms with the current limit.
      #
      # Implementations of this method are not guaranteed
      # to be side-effect free.
      #
      # @return [Boolean] whether a resource conforms with the current limit
      def allow?(size); end

      # The effective rate limiting ratio based on
      # recent calls to `allow?`.
      #
      # @return [Float] recent allowance ratio
      def effective_rate; end
    end

    # Implementation of the Token Bucket metering algorithm
    # for rate limiting.
    #
    # @see https://en.wikipedia.org/wiki/Token_bucket Token bucket
    class TokenBucket < RateLimiter
      attr_reader :rate, :max_tokens

      # @param rate [Numeric] Allowance rate, in units per second
      #  if rate is negative, always allow
      #  if rate is zero, never allow
      # @param max_tokens [Numeric] Limit of available tokens
      def initialize(rate, max_tokens = rate)
        @rate = rate
        @max_tokens = max_tokens

        @tokens = max_tokens
        @total_messages = 0
        @conforming_messages = 0
        @last_refill = Utils::Time.get_time
      end

      # Checks if a message of provided +size+
      # conforms with the current bucket limit.
      #
      # If it does, return +true+ and remove +size+
      # tokens from the bucket.
      # If it does not, return +false+ without affecting
      # the tokens form the bucket.
      #
      # @return [Boolean] +true+ if message conforms with current bucket limit
      def allow?(size)
        return false if @rate.zero?
        return true if @rate < 0

        refill_since_last_message

        increment_total_count

        return false if @tokens < size

        increment_conforming_count

        @tokens -= size

        true
      end

      # Ratio of 'conformance' per 'total messages' checked
      # on this bucket.
      #
      # Returns +1.0+ when no messages have been checked yet.
      #
      # @return [Float] Conformance ratio, between +[0,1]+
      def effective_rate
        return 0.0 if @rate.zero?
        return 1.0 if @rate < 0 || @total_messages.zero?

        @conforming_messages.to_f / @total_messages
      end

      # @return [Numeric] number of tokens currently available
      def available_tokens
        @tokens
      end

      private

      def refill_since_last_message
        now = Utils::Time.get_time
        elapsed = now - @last_refill

        refill_tokens(@rate * elapsed)

        @last_refill = now
      end

      def refill_tokens(size)
        @tokens += size
        @tokens = @max_tokens if @tokens > @max_tokens
      end

      def increment_total_count
        @total_messages += 1
      end

      def increment_conforming_count
        @conforming_messages += 1
      end
    end

    # \RateLimiter that accepts all resources,
    # with no limits.
    class UnlimitedLimiter < RateLimiter
      # @return [Boolean] always +true+
      def allow?(_)
        true
      end

      # @return [Float] always 100%
      def effective_rate
        1.0
      end
    end
  end
end
