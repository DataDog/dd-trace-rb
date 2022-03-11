# typed: false

module Datadog
  module Profiling
    # Used to wrap a ddprof_ffi_Profile in a Ruby object and expose Ruby-level serialization APIs
    # Methods prefixed with _native_ are implemented in `stack_recorder.c`
    class StackRecorder
      def serialize
        status, result = self.class._native_serialize(self)

        if status == :ok
          start, finish, encoded_pprof = result

          [start, finish, encoded_pprof]
        else
          error_message = result

          Datadog.logger.error("Failed to serialize profiling data: #{error_message}")

          nil
        end
      end
    end
  end
end
