require 'ffi'

module Datadog
  module Profiling
    module Ext
      # C-struct for retrieving clock ID from pthread
      class CClockId < FFI::Struct
        layout :value, :int
      end

      # Extension used to enable CPU-time profiling via use of Pthread's `getcpuclockid`.
      module CThread
        extend FFI::Library
        ffi_lib ['pthread', 'libpthread.so.0']
        attach_function :pthread_self, [], :ulong
        attach_function :pthread_getcpuclockid, [:ulong, CClockId], :int

        def self.prepended(base)
          # Threads that have already been created, will not have resolved
          # a thread/clock ID. This is because these IDs can only be resolved
          # from within the thread's execution context, which we do not control.
          #
          # We can mitigate this for the current thread via #update_native_ids,
          # since we are currently running within its execution context. We cannot
          # do this for any other threads that may have been created already.
          # (This is why it's important that CThread is applied before anything else runs.)
          base.current.send(:update_native_ids) if base.current.is_a?(CThread)
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
          wrapped_block.ruby2_keywords if wrapped_block.respond_to?(:ruby2_keywords, true)

          super(*args, &wrapped_block)
        end
        ruby2_keywords :initialize if respond_to?(:ruby2_keywords, true)

        def clock_id
          update_native_ids if forked?
          defined?(@clock_id) && @clock_id
        end

        def cpu_time(unit = :float_second)
          return unless clock_id && ::Process.respond_to?(:clock_gettime)
          ::Process.clock_gettime(clock_id, unit)
        end

        def cpu_time_instrumentation_installed?
          # If this thread was started before this module was added to Thread OR if something caused the initialize
          # method above not to be properly called on new threads, this instance variable is never defined (never set to
          # any value at all, including nil).
          #
          # Thus, we can use @clock_id as a canary to detect a thread that has missing instrumentation, because we
          # know that in initialize above we always set this variable to nil.
          defined?(@clock_id) != nil
        end

        private

        # Retrieves number of classes from runtime
        def forked?
          ::Process.pid != (@pid ||= nil)
        end

        def update_native_ids
          # Can only resolve if invoked from same thread.
          return unless ::Thread.current == self

          @pid = ::Process.pid
          @native_thread_id = get_native_thread_id
          @clock_id = get_clock_id(@native_thread_id)
        end

        def get_native_thread_id
          return unless ::Thread.current == self

          # NOTE: Only returns thread ID for thread that evaluates this call.
          #       a.k.a. evaluating `thread_a.get_native_thread_id` from within
          #       `thread_b` will return `thread_b`'s thread ID, not `thread_a`'s.
          pthread_self
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
