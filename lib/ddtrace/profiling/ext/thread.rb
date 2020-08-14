require 'ffi'

module Datadog
  module Profiling
    module Ext
      # C-struct for retrieving clock ID from pthread
      class CClockId < FFI::Struct
        layout :value, :int
      end

      # Extensions for pthread-backed Ruby threads, to retrieve
      # the thread ID, clock ID, and CPU time.
      module CThread
        extend FFI::Library
        ffi_lib 'ruby', 'pthread'
        attach_function :rb_nativethread_self, [], :ulong
        attach_function :pthread_getcpuclockid, [:ulong, CClockId], :int

        def self.prepended(base)
          # Be sure to update the current thread too; as it wouldn't have been set.
          ::Thread.current.send(:update_native_ids)
        end

        attr_reader \
          :native_thread_id

        def initialize(*args)
          @pid = ::Process.pid
          @native_thread_id = nil
          @clock_id = nil

          # Wrap the work block with our own
          # so we can retrieve the native thread ID within the thread's context.
          wrapped_block = proc do |*t_args|
            # Set native thread ID & clock ID
            update_native_ids
            yield(*t_args)
          end

          super(*args, &wrapped_block)
        end

        def clock_id
          update_native_ids if forked?
          @clock_id ||= nil
        end

        def cpu_time(unit = :float_second)
          return unless clock_id && ::Process.respond_to?(:clock_gettime)
          ::Process.clock_gettime(clock_id, unit)
        end

        private

        # Retrieves number of classes from runtime
        def forked?
          ::Process.pid != (@pid ||= nil)
        end

        def update_native_ids
          @pid = ::Process.pid
          @native_thread_id = get_native_thread_id
          @clock_id = get_clock_id(@native_thread_id)
        end

        def get_native_thread_id
          # Only run if invoked from same thread, otherwise
          # it will receive incorrect thread ID.
          return unless ::Thread.current == self

          # NOTE: Only returns thread ID for thread that evaluates this call.
          #       a.k.a. evaluating `thread_a.get_native_thread_id` from within
          #       `thread_b` will return `thread_b`'s thread ID, not `thread_a`'s.
          rb_nativethread_self
        end

        def get_clock_id(pthread_id)
          return unless pthread_id && alive?

          # Build a struct, pass it to Pthread's getcpuclockid function.
          clock = CClockId.new
          clock[:value] = 0
          pthread_getcpuclockid(pthread_id, clock).zero? ? clock[:value] : nil
        end
      end
    end
  end
end
