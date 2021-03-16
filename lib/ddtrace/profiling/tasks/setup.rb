require 'ddtrace'
require 'ddtrace/profiling'
require 'ddtrace/profiling/ext/cpu'
require 'ddtrace/profiling/ext/forking'

module Datadog
  module Profiling
    module Tasks
      # Takes care of loading our extensions/monkey patches to handle fork() and CPU profiling.
      class Setup
        def run
          ONLY_ONCE.run do
            begin
              activate_forking_extensions
              activate_cpu_extensions
              setup_at_fork_hooks
            rescue StandardError, ScriptError => e
              log "[DDTRACE] Main extensions unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
            end
          end
        end

        private

        def activate_forking_extensions
          if Ext::Forking.supported?
            Ext::Forking.apply!
          elsif Datadog.configuration.profiling.enabled
            # Log warning if profiling was supposed to be activated.
            log '[DDTRACE] Forking extensions skipped; forking not supported.'
          end
        rescue StandardError, ScriptError => e
          log "[DDTRACE] Forking extensions unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
        end

        def activate_cpu_extensions
          if Ext::CPU.supported?
            Ext::CPU.apply!
          elsif Datadog.configuration.profiling.enabled
            # Log warning if profiling was supposed to be activated.
            log "[DDTRACE] CPU profiling skipped because native CPU time is not supported: #{Ext::CPU.unsupported_reason}."
          end
        rescue StandardError, ScriptError => e
          log "[DDTRACE] CPU profiling unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
        end

        def setup_at_fork_hooks
          if Process.respond_to?(:at_fork)
            Process.at_fork(:child) do
              begin
                # When Ruby forks, clock IDs for each of the threads
                # will change. We can only update these IDs from the
                # execution context of the thread that owns it.
                # This hook will update the IDs for the main thread
                # after a fork occurs.
                Thread.current.send(:update_native_ids) if Thread.current.respond_to?(:update_native_ids, true)

                # Restart profiler, if enabled
                Datadog.profiler.start if Datadog.profiler
              rescue StandardError => e
                log "[DDTRACE] Error during post-fork hooks. Cause: #{e.message} Location: #{e.backtrace.first}"
              end
            end
          end
        end

        def log(message)
          # Print to STDOUT for now because logging may not be setup yet...
          puts message
        end

        # Small helper class to allow some piece of code to be run only once
        class OnlyOnce
          def initialize
            @mutex = Mutex.new
            @ran_once = false
          end

          def run
            @mutex.synchronize do
              return if @ran_once

              @ran_once = true

              yield
            end
          end

          private

          def reset_ran_once_state_for_tests
            @ran_once = false
          end
        end
        ONLY_ONCE = OnlyOnce.new

        private_constant :OnlyOnce
        private_constant :ONLY_ONCE
      end
    end
  end
end
