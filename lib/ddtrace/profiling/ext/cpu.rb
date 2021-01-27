module Datadog
  module Profiling
    module Ext
      # Extensions for CPU
      module CPU
        FFI_MINIMUM_VERSION = Gem::Version.new('1.0')
        THREAD_HOOK = :datadog_profiling_cpu_hook

        def self.supported?
          RUBY_PLATFORM != 'java' \
            && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.1') \
            && !Gem.loaded_specs['ffi'].nil? \
            && Gem.loaded_specs['ffi'].version >= FFI_MINIMUM_VERSION
        end

        def self.apply!
          return false unless supported?

          # Applying CThread to Thread will ensure any new threads
          # will provide a thread/clock ID for CPU timing.
          require 'ddtrace/profiling/ext/cthread'
          ::Thread.send(:prepend, Profiling::Ext::CThread)

          # Applying hooks will allow any existing threads to update
          # their thread/clock IDs so their CPU timings can be measured.
          apply_hooks!
        end

        def self.apply_hooks!
          # Threads that have already been created, will not have resolved
          # a thread/clock ID. This is because these IDs can only be resolved
          # from within the thread's execution context, which we do not control.
          #
          # We can work around this by applying trace hooks to capture each thread
          # from within its own execution context, resolving the thread/clock IDs,
          # then disabling the hook so it doesn't re-run needlessly.
          Thread.list.each do |thread|
            # Only attempt to hook into threads that are instrumented
            next unless thread.is_a?(CThread)

            # TracePoint supports filtering by thread for Ruby 2.7+
            if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7') && defined?(TracePoint)
              thread[THREAD_HOOK] = TracePoint.new(:line) do |tp|
                current_thread = Thread.current

                begin
                  current_thread.send(:update_native_ids)
                rescue StandardError => e
                  log "ERROR: Failed to update thread/clock IDs for Thread #{current_thread.object_id}.\nCause: #{e.message}\nLocation: #{e.backtrace.first}"
                ensure
                  current_thread[THREAD_HOOK].disable
                end
              end

              thread[THREAD_HOOK].enable(target_thread: thread)
            # Otherwise use Thread#set_trace_func to scope per thread
            else
              thread[THREAD_HOOK] = proc {
                current_thread = Thread.current

                begin
                  current_thread.send(:update_native_ids)
                rescue StandardError => e
                  log "ERROR: Failed to update thread/clock IDs for Thread #{current_thread.object_id}.\nCause: #{e.message}\nLocation: #{e.backtrace.first}"
                ensure
                  # Disable hook no matter what, to prevent loops
                  # if an error is encountered.
                  current_thread.set_trace_func(nil)
                end
              }

              thread.set_trace_func(thread[THREAD_HOOK])
            end
          end
        end

        private

        def self.log(message)
          # Print to STDOUT for now because logging may not be setup yet...
          puts message
        end
      end
    end
  end
end
