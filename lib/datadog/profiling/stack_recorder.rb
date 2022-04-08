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

      # Used only for Ruby 2.2 and below which don't have the native `rb_time_timespec_new` API
      # Called from native code
      def self.ruby_time_from(timespec_seconds, timespec_nanoseconds)
        Time.at(0).utc + timespec_seconds + (timespec_nanoseconds.to_r / 1_000_000_000)
      end
    end
  end
end
