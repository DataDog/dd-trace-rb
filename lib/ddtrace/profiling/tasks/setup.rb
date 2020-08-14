module Datadog
  module Profiling
    module Tasks
      # Sets up profiling for the application
      class Setup
        def run
          activate_main_extensions
          activate_thread_extensions
        end

        def activate_main_extensions
          # Add forking extensions
          require 'ddtrace/profiling/ext/forking'
          Ext::Forking.apply!
        rescue StandardError, ScriptError => e
          puts "[DDTRACE] Forking extensions unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
        end

        def activate_thread_extensions
          # Activate CPU timings
          require 'ddtrace/profiling/ext/thread'
          ::Thread.send(:prepend, Profiling::Ext::CThread)
        rescue StandardError, ScriptError => e
          puts "[DDTRACE] CPU profiling unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
        end
      end
    end
  end
end
