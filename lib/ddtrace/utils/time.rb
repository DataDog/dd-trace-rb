module Datadog
  module Utils
    # Common database-related utility functions.
    module Time
      PROCESS_TIME_SUPPORTED = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')

      module_function

      def get_time
        PROCESS_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : ::Time.now.to_f
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
