require_relative '../../core/utils/only_once'
require_relative '../ext/forking'

module Datadog
  module Profiling
    module Tasks
      # Takes care of loading our extensions/monkey patches to handle fork() and validating if CPU-time profiling is usable
      class Setup
        ACTIVATE_EXTENSIONS_ONLY_ONCE = Core::Utils::OnlyOnce.new

        def run
          ACTIVATE_EXTENSIONS_ONLY_ONCE.run do
            begin
              check_if_cpu_time_profiling_is_supported
              activate_forking_extensions
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

        def activate_forking_extensions
          if Ext::Forking.supported?
            Ext::Forking.apply!
          elsif Datadog.configuration.profiling.enabled
            Datadog.logger.debug('Profiler forking extensions skipped; forking not supported.')
          end
        rescue StandardError, ScriptError => e
          Datadog.logger.warn do
            "Profiler forking extensions unavailable. Cause: #{e.class.name} #{e.message} " \
            "Location: #{Array(e.backtrace).first}"
          end
        end

        def check_if_cpu_time_profiling_is_supported
          unsupported = cpu_time_profiling_unsupported_reason

          if unsupported
            Datadog.logger.info do
              'CPU time profiling skipped because native CPU time is not supported: ' \
              "#{unsupported}. Profiles containing 'Wall time' data will still be reported."
            end
          end
        end

        def setup_at_fork_hooks
          if Process.respond_to?(:at_fork)
            Process.at_fork(:child) do
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

        def cpu_time_profiling_unsupported_reason
          # NOTE: Only the first matching reason is returned, so try to keep a nice order on reasons

          if RUBY_ENGINE == 'jruby'
            'JRuby is not supported'
          elsif RUBY_PLATFORM.include?('darwin')
            'Feature requires Linux; macOS is not supported'
          elsif RUBY_PLATFORM =~ /(mswin|mingw)/
            'Feature requires Linux; Windows is not supported'
          elsif !RUBY_PLATFORM.include?('linux')
            "Feature requires Linux; #{RUBY_PLATFORM} is not supported"
          end
        end
      end
    end
  end
end
