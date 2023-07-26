require 'date'
require 'json'
require 'rbconfig'
require_relative '../../core/diagnostics/environment_logger'

module Datadog
  module Profiling
    module Diagnostics
      class EnvironmentLogger
        extend Core::Diagnostics::EnvironmentLogging

        def self.prefix
          'PROFILING'
        end
      end

      class EnvironmentCollector
        def self.collect!
          {
            profiling_enabled: profiling_enabled
          }
        end

        def self.profiling_enabled
          !!Datadog.configuration.profiling.enabled
        end
      end
    end
  end
end
