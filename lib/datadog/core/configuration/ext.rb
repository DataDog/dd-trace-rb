module Datadog
  module Core
    module Configuration
      # Constants for configuration settings
      # e.g. Env vars, default values, enums, etc...
      module Ext
        # @public_api
        module Diagnostics
          ENV_DEBUG_ENABLED = 'DD_TRACE_DEBUG'.freeze
          ENV_HEALTH_METRICS_ENABLED = 'DD_HEALTH_METRICS_ENABLED'.freeze
          ENV_STARTUP_LOGS_ENABLED = 'DD_TRACE_STARTUP_LOGS'.freeze
        end

        module Metrics
          ENV_DEFAULT_PORT = 'DD_METRIC_AGENT_PORT'.freeze
        end

        module Transport
          ENV_DEFAULT_HOST = 'DD_AGENT_HOST'.freeze
        end
      end
    end
  end
end
