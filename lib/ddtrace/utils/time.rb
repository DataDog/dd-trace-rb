module Datadog
  module Utils
    # Common database-related utility functions.
    module Time
      module_function

      # Current monotonic time.
      # Falls back to `now` if monotonic clock
      # is not available.
      #
      # @return [Float] in seconds, since some unspecified starting point
      def get_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      # Current wall time.
      #
      # @return [Time] current time object
      def now
        ::Time.now
      end

      # Overrides the implementation of `#now
      # with the provided callable.
      #
      # Overriding the method `#now` instead of
      # indirectly calling `block` removes
      # one level of method call overhead.
      #
      # @param block [Proc] block that returns a `Time` object representing the current wall time
      def now_provider=(block)
        define_singleton_method(:now, &block)
      end

      def measure
        before = get_time
        yield
        after = get_time
        after - before
      end
    end
  end
end
