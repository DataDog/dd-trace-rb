require 'date'
require 'json'
require 'rbconfig'
require_relative '../../core/diagnostics/environment_logger'

module Datadog
  module Profiling
    module Diagnostics
      class EnvironmentLogger < Core::Diagnostics::EnvironmentLogging
        def self.log!
          if log_checks!
            @logger ||= EnvironmentLogger.new
            @logger.log!
          end
        end

        def log!
          data = EnvironmentCollector.collect!
          data.reject! { |_, v| v.nil? } # Remove empty values from hash output
          log_configuration!('PROFILING'.freeze, data.to_json)
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
