module Datadog
  module Utils
    # Circuit breaker - prevents cascading failures
    class CircuitBreaker
      CircuitBreakerException = Class.new(RuntimeError)
      SUCCESS = 1
      FAILURE = 0
      MAX_ROLLING_RESULTS = 20

      def initialize(failures_threshold = 0.5, retry_after = 10000)
        @failures = 0
        @rolling_results = Array.new(MAX_ROLLING_RESULTS) { SUCCESS }
        @failures_threshold = failures_threshold
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

      def close
        @opened_at = nil
      end

      def failing?
        error_rate > @failures_threshold
      end

      def open?
        !@opened_at.nil?
      end

      def retry?
        return true if @opened_at.nil?

        elapsed = time_now - @opened_at
        elapsed > @retry_after
      end

      def with
        return yield if @failures_threshold <= 0 # disable CircuitBreaker

        raise CircuitBreakerException, @last_exception if open? && !retry?

        begin
          res = yield
          push_result(SUCCESS)
          close
          res
        rescue StandardError => ex
          push_result(FAILURE)
          @last_exception = ex
          open if failing?
          raise ex
        end
      end

      private

      def error_rate
        1 - @rolling_results.inject(:+).to_f / @rolling_results.length
      end

      def push_result(res)
        @rolling_results.shift
        @rolling_results.push(res)
      end
    end
  end
end
