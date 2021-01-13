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
          check_warnings!
          activate_main_extensions
          autostart_profiler
        end

        def activate_main_extensions
          # Activate extensions first
          activate_forking_extensions
          activate_cpu_extensions

          # Setup at_fork hook:
          # When Ruby forks, clock IDs for each of the threads
          # will change. We can only update these IDs from the
          # execution context of the thread that owns it.
          # This hook will update the IDs for the main thread
          # after a fork occurs.
          if Process.respond_to?(:at_fork)
            Process.at_fork(:child) do
              # Update current thread clock, if available.
              # (Be careful not to raise an error here.)
              if Thread.current.respond_to?(:update_native_ids, true)
                Thread.current.send(:update_native_ids)
              end
            end
          end
        rescue StandardError, ScriptError => e
          log "[DDTRACE] Main extensions unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
        end

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

        def check_warnings!
          warn_if_incompatible_rollbar_gem_detected
        end

        # See https://github.com/rollbar/rollbar-gem/pull/1018 for details on the incompatibility
        def warn_if_incompatible_rollbar_gem_detected
          incompatible_rollbar_versions = Gem::Requirement.new('<= 3.1.1')

          if Gem::Specification.find_all_by_name('rollbar', incompatible_rollbar_versions).any?
            log "[DDTRACE] Incompatible version of the rollbar gem is installed (#{incompatible_rollbar_versions}). " \
              'Loading this version of the rollbar gem will disable ddtrace\'s CPU profiling. ' \
              'Please upgrade to the latest rollbar version. ' \
              'See https://github.com/rollbar/rollbar-gem/pull/1018 for details.'
          end
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
