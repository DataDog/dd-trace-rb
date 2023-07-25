require 'date'
require 'json'
require 'rbconfig'
require_relative '../../core/diagnostics/environment_logger'

module Datadog
  module Profiling
    module Diagnostics
      # Collects profiling environment information for diagnostic logging
      module ProfilingEnvironmentCollector
        def profiling_enabled
          !!Datadog.configuration.profiling.enabled
        end

        def collect!(**data)
          super.merge(
            profiling_enabled: profiling_enabled
          )
        end
      end

      Core::Diagnostics::EnvironmentCollector.prepend(ProfilingEnvironmentCollector)
    end
  end
end
