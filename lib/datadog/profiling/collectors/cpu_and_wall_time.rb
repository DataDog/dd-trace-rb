module Datadog
  module Profiling
    module Collectors
      # Used to periodically sample threads, recording elapsed CPU-time and Wall-time between samples.
      # Triggering of this component (e.g. deciding when to take a sample) is implemented in
      # Collectors::CpuAndWallTimeWorker.
      # The stack collection itself is handled using the Datadog::Profiling::Collectors::Stack.
      # Almost all of this class is implemented as native code.
      #
      # Methods prefixed with _native_ are implemented in `collectors_cpu_and_wall_time.c`
      class CpuAndWallTime
        def initialize(recorder:, max_frames:, tracer:)
          tracer_context_key = safely_extract_context_key_from(tracer)
          self.class._native_initialize(self, recorder, max_frames, tracer_context_key)
        end

        def inspect
          # Compose Ruby's default inspect with our custom inspect for the native parts
          result = super()
          result[-1] = "#{self.class._native_inspect(self)}>"
          result
        end

        def reset_after_fork
          self.class._native_reset_after_fork(self)
        end

        private

        def safely_extract_context_key_from(tracer)
          provider = tracer && tracer.respond_to?(:provider) && tracer.provider

          return unless provider

          context = provider.instance_variable_get(:@context)
          context && context.instance_variable_get(:@key)
        end
      end
    end
  end
end
