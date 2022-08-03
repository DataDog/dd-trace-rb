# typed: false

module Datadog
  module Profiling
    # Stores stack samples in a native libdatadog data structure and expose Ruby-level serialization APIs
    # Note that `record_sample` is only accessible from native code.
    # Methods prefixed with _native_ are implemented in `stack_recorder.c`
    class StackRecorder
      def initialize
        # This mutex works in addition to the fancy C-level mutexes we have in the native side (see the docs there).
        # It prevents multiple Ruby threads calling serialize at the same time -- something like
        # `10.times { Thread.new { stack_recorder.serialize } }`.
        # This isn't something we expect to happen normally, but because it would break the assumptions of the
        # C-level mutexes (that there is a single serializer thread), we add it here as an extra safeguard against it
        # accidentally happening.
        @no_concurrent_synchronize_mutex = Thread::Mutex.new

        GC::Profiler.enable
        @gc_at_last_export = GC::Profiler.total_time
      end

      def serialize
        status, result = @no_concurrent_synchronize_mutex.synchronize { self.class._native_serialize(self) }

        if status == :ok
          start, finish, encoded_pprof = result

          time_in_gc_now = GC::Profiler.total_time
          time_in_gc_spent = time_in_gc_now - @gc_at_last_export
          @gc_at_last_export = time_in_gc_now

          Datadog.logger.debug { "Encoded profile covering #{start.iso8601} to #{finish.iso8601} (#{time_in_gc_spent} spent in GC)" }

          [start, finish, encoded_pprof]
        else
          error_message = result

          Datadog.logger.error("Failed to serialize profiling data: #{error_message}")

          nil
        end
      end

      # Used only for Ruby 2.2 which doesn't have the native `rb_time_timespec_new` API; called from native code
      def self.ruby_time_from(timespec_seconds, timespec_nanoseconds)
        Time.at(0).utc + timespec_seconds + (timespec_nanoseconds.to_r / 1_000_000_000)
      end
    end
  end
end
