# typed: false

module Datadog
  module Profiling
    module Collectors
      # Used to periodically (time-based) sample threads, recording elapsed CPU-time and Wall-time between samples.
      # The stack collection itself is handled using the Datadog::Profiling::Collectors::Stack.
      #
      # Methods prefixed with _native_ are implemented in `collectors_cpu_and_wall_time.c`
      class CpuAndWallTime
        def initialize(recorder:, max_frames:)
          self.class._native_initialize(self, recorder, max_frames)
        end

        # This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTime behavior using RSpec.
        # It SHOULD NOT be used for other purposes.
        def sample
          self.class._native_sample(self)
        end
      end
    end
  end
end
