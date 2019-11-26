# TODO: move to a folder outside of 'ddtrace/sampling', as this is technically a generic rate limiter?
module Datadog
  module Sampling
    # TODO: Write class documentation
    # [Class documentation]
    class RateLimiter
      # TODO
      # @return [Boolean]
      def allow?(size); end

      # TODO
      # @return [Float]
      def effective_rate; end
    end

    # Implementation of the Token Bucket metering algorithm.
    #
    # TODO: Find more canonical link: https://en.wikipedia.org/wiki/Token_bucket
    #
    class TokenBucket < RateLimiter
      attr_reader :rate, :max_tokens

      def initialize(rate, max_tokens = rate)
        @rate = rate
        @max_tokens = max_tokens

        @tokens = max_tokens
        @total_messages = 0
        @conforming_messages = 0
        @last_refill = now
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
        return 1.0 if @total_messages.zero?

        @conforming_messages.to_f / @total_messages
      end

      # @return [Numeric] number of tokens currently available
      def available_tokens
        @tokens
      end

      private

      def refill_since_last_message
        now = now()
        elapsed = now - @last_refill

        refill_tokens(@rate * elapsed)

        @last_refill = now
      end

      def refill_tokens(size)
        @tokens += size
        @tokens = @max_tokens if @tokens > @max_tokens
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def increment_total_count
        @total_messages += 1
      end

      def increment_conforming_count
        @conforming_messages += 1
      end
    end

    # TODO: This class name is so bad, yet so good.
    # [Class documentation]
    class UnlimitedLimiter < RateLimiter
      # TODO
      # @return [Boolean]
      def allow?(_size)
        true
      end

      # TODO
      # @return [Float]
      def effective_rate
        1.0
      end
    end
  end
end
