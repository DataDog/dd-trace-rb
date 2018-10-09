module Datadog
  module Utils
    # Circuit breaker - prevents cascading failures
    class CircuitBreaker
      CircuitBreakerException = Class.new(RuntimeError)

      def initialize(max_failures = 5, retry_after = 10000)
        @failures = 0
        @max_failures = max_failures
        @retry_after = retry_after # time to attempt re-enabling failing circuit breaker msec
        @opened_at = nil
        @last_exception = nil
      end

      def time_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
      end

      def open
        @opened_at = time_now
      end

      def failing?
        @failures > @max_failures
      end

      def open?
        !@opened_at.nil?
      end

      def retry?
        return true if @opened_at.nil?

        elapsed = time_now - @opened_at
        elapsed > @retry_after
      end

      def reset!
        @opened_at = nil
        @failures = 0
      end

      def with
        return yield if @max_failures <= 0 # disable CircuitBreaker

        raise CircuitBreakerException, @last_exception if open? && !retry?

        begin
          res = yield
          reset!
          res
        rescue StandardError => ex
          @failures += 1
          @last_exception = ex
          open if failing?
          raise ex
        end
      end
    end
  end
end
