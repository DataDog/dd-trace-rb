require 'ddtrace'
require 'ddtrace/profiling'
require 'ddtrace/profiling/ext/cpu'
require 'ddtrace/profiling/ext/forking'

module Datadog
  module Profiling
    module Tasks
      # Sets up profiling for the application
      class Setup
        def run
          activate_main_extensions
          activate_cpu_extensions
          autostart_profiler
        end

        def activate_main_extensions
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
            log '[DDTRACE] CPU profiling skipped; native CPU time is not supported.'
          end
        rescue StandardError, ScriptError => e
          log "[DDTRACE] CPU profiling unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
        end

        def autostart_profiler
          if Datadog::Profiling.supported?
            # Start the profiler
            Datadog.profiler.start if Datadog.profiler

            # Setup at_fork hook:
            # When Ruby forks, threads running in the parent process
            # won't be restarted in the child process. This hook will
            # restart the profiler in the child process when this happens.
            if Process.respond_to?(:at_fork)
              Process.at_fork(:child) { Datadog.profiler.start if Datadog.profiler }
            end
          elsif Datadog.configuration.profiling.enabled
            # Log warning if profiling was supposed to be activated.
            log '[DDTRACE] Profiling did not autostart; profiling not supported.'
          end
        rescue StandardError => e
          log "[DDTRACE] Could not autostart profiling. Cause: #{e.message} Location: #{e.backtrace.first}"
        end

        private

        def log(message)
          # Print to STDOUT for now because logging may not be setup yet...
          puts message
        end
      end
    end
  end
end
