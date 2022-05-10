# typed: false

module Datadog
  module Profiling
    module Collectors
      # Used to periodically (time-based) sample threads, recording elapsed CPU-time and Wall-time between samples.
      # The stack collection itself is handled using the Datadog::Profiling::Collectors::Stack.
      #
      # Methods prefixed with _native_ are implemented in `collectors_cpu_and_wall_time.c`
      class CpuAndWallTime

      end
    end
  end
end
