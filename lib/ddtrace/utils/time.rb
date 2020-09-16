module Datadog
  module Utils
    # Common database-related utility functions.
    module Time
      PROCESS_TIME_SUPPORTED = Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1.0')

      module_function

      def get_time
        PROCESS_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : timecop_supported_time_now.to_f
      end

      # TODO: provide a `c.use timecop` type interface to give this proper support
      # Patch for api integration client
      def timecop_supported_time_now
        (::Time.respond_to?(:now_without_mock_time) ? ::Time.now_without_mock_time : ::Time.now)
      end
    end
  end
end
