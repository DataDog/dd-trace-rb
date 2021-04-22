require 'ffi'

module Datadog
  module Profiling
    module Ext
      # C-struct for retrieving clock ID from pthread
      class CClockId < FFI::Struct
        layout :value, :int
      end

      # Enables interfacing with pthread via FFI
      module NativePthread
        extend FFI::Library
        ffi_lib ['pthread', 'libpthread.so.0']
        attach_function :pthread_self, [], :ulong
        attach_function :pthread_getcpuclockid, [:ulong, CClockId], :int

        # NOTE: Only returns thread ID for thread that evaluates this call.
        #       a.k.a. evaluating `get_native_thread_id(thread_a)` from within
        #       `thread_b` will return `thread_b`'s thread ID, not `thread_a`'s.
        def self.get_native_thread_id(thread)
          return unless ::Thread.current == thread

          pthread_self
        end

        def self.get_clock_id(thread, pthread_id)
          return unless ::Thread.current == thread && pthread_id

          clock = CClockId.new
          clock[:value] = 0
          pthread_getcpuclockid(pthread_id, clock).zero? ? clock[:value] : nil
        end
      end

      # Extension used to enable CPU-time profiling via use of pthread's `getcpuclockid`.
      module CThread
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

        # Process::Waiter crash workaround:
        #
        # This is a workaround for a Ruby VM segfault (usually something like
        # "[BUG] Segmentation fault at 0x0000000000000008") in the affected Ruby versions.
        # See https://bugs.ruby-lang.org/issues/17807 and the regression tests added to this module's specs for details.
        #
        # In those Ruby versions, there's a very special subclass of `Thread` called `Process::Waiter` that causes VM
        # crashes whenever something tries to read its instance variables. This subclass of thread only shows up when
        # the `Process.detach` API gets used.
        # In this module's specs you can find crash regression tests that include a way of reproducing it.
        #
        # The workaround is to use `defined?` to check first if the instance variable exists. This seems to be fine
        # with Ruby.
        # Note that this crash doesn't affect `@foo ||=` nor instance variable writes (after the first write ever of any
        # instance variable on a `Process::Waiter`, then further reads and writes to that or any other instance are OK;
        # it looks like there's some lazily-created structure that is missing and did not get created).
        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3') &&
           Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7')
          attr_reader :native_thread_id
        else
          def native_thread_id
            defined?(@native_thread_id) && @native_thread_id
          end
        end

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

        def clock_id
          update_native_ids if forked?
          defined?(@clock_id) && @clock_id
        end

        def forked?
          ::Process.pid != (@pid ||= nil)
        end

        def update_native_ids
          # Can only resolve if invoked from same thread
          return unless ::Thread.current == self

          @pid = ::Process.pid
          @native_thread_id = NativePthread.get_native_thread_id(self)
          @clock_id = NativePthread.get_clock_id(self, @native_thread_id)
        end
      end

      # Threads in Ruby can be started by creating a new instance of `Thread` (or a subclass) OR by calling
      # `start`/`fork` on `Thread` (or a subclass).
      #
      # This module intercepts calls to `start`/`fork`, ensuring that the `update_native_ids` operation is correctly
      # called once the new thread starts.
      #
      # Note that unlike CThread above, this module should be prepended to the `Thread`'s singleton class, not to
      # the class.
      module WrapThreadStartFork
        def start(*args)
          # Wrap the work block with our own
          # so we can retrieve the native thread ID within the thread's context.
          wrapped_block = proc do |*t_args|
            # Set native thread ID & clock ID
            ::Thread.current.send(:update_native_ids)
            yield(*t_args)
          end
          wrapped_block.ruby2_keywords if wrapped_block.respond_to?(:ruby2_keywords, true)

          super(*args, &wrapped_block)
        end
        ruby2_keywords :start if respond_to?(:ruby2_keywords, true)

        alias fork start
      end
    end
  end
end
