module Datadog
  module Utils
    # Common time-related utility functions
    module Time
      # Check for architecture-dependent support
      PROCESS_TIME_SUPPORTED = defined? Process::CLOCK_MONOTONIC
      THREAD_CPU_TIME_SUPPORTED = defined? Process::CLOCK_THREAD_CPUTIME_ID

      module_function

      # @return [Float] if supported, monotonic time in seconds; system wall time otherwise
      def get_time
        PROCESS_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_MONOTONIC) : ::Time.now.to_f
      end

      # @return [Float] if supported, total thread cpu time used in seconds; +nil+ otherwise
      def get_thread_cpu_time
        THREAD_CPU_TIME_SUPPORTED ? Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID) : nil
      end
    end
  end
end
