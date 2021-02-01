module Datadog
  module Utils
    # Common database-related utility functions.
    module Time
      PROCESS_TIME_SUPPORTED = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')

      module_function

      # Current monotonic time.
      # Falls back to `now` if monotonic clock
      # is not available.
      #
      # @return [Float] in seconds, since some unspecified starting point
      def get_time
        PROCESS_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : now.to_f
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
    end
  end
end
