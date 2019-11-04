module Datadog
  module Sampling
    # Implementation of the Token Bucket metering algorithm.
    #
    # TODO: Find more canonical link: https://en.wikipedia.org/wiki/Token_bucket
    #
    class TokenBucket
      attr_reader :rate, :max_tokens

      def initialize(rate, max_tokens = rate)
        @rate = rate
        @max_tokens = max_tokens

        @tokens = max_tokens
        @total_messages = 0
        @conforming_messages = 0
        @last_refill = now
      end

      def conform?(size)
        refill_since_last_message

        increment_total_count

        return false if @tokens < size

        increment_conforming_count

        @tokens -= size

        true
      end

      def available_tokens
        @tokens
      end

      def conformance_rate
        return 1.0 if @total_messages == 0

        @conforming_messages.to_f / @total_messages
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
  end
end