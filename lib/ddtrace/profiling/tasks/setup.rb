require 'ddtrace'
require 'ddtrace/utils/only_once'
require 'ddtrace/profiling'
require 'ddtrace/profiling/ext/cpu'
require 'ddtrace/profiling/ext/forking'

module Datadog
  module Profiling
    module Tasks
      # Takes care of loading our extensions/monkey patches to handle fork() and CPU profiling.
      class Setup
        ACTIVATE_EXTENSIONS_ONLY_ONCE = Datadog::Utils::OnlyOnce.new

        def run
          ACTIVATE_EXTENSIONS_ONLY_ONCE.run do
            begin
              activate_forking_extensions
              activate_cpu_extensions
              setup_at_fork_hooks
            rescue StandardError, ScriptError => e
              Datadog.logger.warn { "Profiler extensions unavailable. Cause: #{e.message} Location: #{e.backtrace.first}" }
            end
          end
        end

        private

        def activate_forking_extensions
          if Ext::Forking.supported?
            Ext::Forking.apply!
          elsif Datadog.configuration.profiling.enabled
            Datadog.logger.debug('Profiler forking extensions skipped; forking not supported.')
          end
        rescue StandardError, ScriptError => e
          Datadog.logger.warn do
            "Profiler forking extensions unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
          end
        end

        def activate_cpu_extensions
          if Ext::CPU.supported?
            Ext::CPU.apply!
          elsif Datadog.configuration.profiling.enabled
            Datadog.logger.info do
              'CPU time profiling skipped because native CPU time is not supported: ' \
              "#{Ext::CPU.unsupported_reason}. Profiles containing Wall time will still be reported."
            end
          end
        rescue StandardError, ScriptError => e
          Datadog.logger.warn do
            "Profiler CPU profiling extensions unavailable. Cause: #{e.message} Location: #{e.backtrace.first}"
          end
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
                Datadog.logger.warn { "Error during post-fork hooks. Cause: #{e.message} Location: #{e.backtrace.first}" }
              end
            end
          end
        end
      end
    end
  end
end
