# frozen_string_literal: true

require_relative '../../core/utils/only_once'
require_relative '../../core/utils/at_fork_monkey_patch'

module Datadog
  module Profiling
    module Tasks
      # Takes care of restarting the profiler when the process forks
      class Setup
        ACTIVATE_EXTENSIONS_ONLY_ONCE = Core::Utils::OnlyOnce.new

        def run
          ACTIVATE_EXTENSIONS_ONLY_ONCE.run do
            begin
              Datadog::Core::Utils::AtForkMonkeyPatch.apply!
              setup_at_fork_hooks
            rescue StandardError, ScriptError => e
              Datadog.logger.warn do
                "Profiler extensions unavailable. Cause: #{e.class.name} #{e.message} " \
                "Location: #{Array(e.backtrace).first}"
              end
            end
          end
        end

        private

        def setup_at_fork_hooks
          Datadog::Core::Utils::AtForkMonkeyPatch.at_fork(:child) do
            begin
              # Restart profiler, if enabled
              Profiling.start_if_enabled
            rescue StandardError => e
              Datadog.logger.warn do
                "Error during post-fork hooks. Cause: #{e.class.name} #{e.message} " \
                "Location: #{Array(e.backtrace).first}"
              end
            end
          end
        end
      end
    end
  end
end
