module Datadog
  module Profiling
    module Tasks
      # Sets up profiling for the application
      class Setup
        def run
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
