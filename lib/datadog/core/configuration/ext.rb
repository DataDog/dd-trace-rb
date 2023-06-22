# frozen_string_literal: true

module Datadog
  module Core
    module Configuration
      # Constants for configuration settings
      # e.g. Env vars, default values, enums, etc...
      module Ext
        # @public_api
        module Diagnostics
          ENV_DEBUG_ENABLED = 'DD_TRACE_DEBUG'
          ENV_HEALTH_METRICS_ENABLED = 'DD_HEALTH_METRICS_ENABLED'
          ENV_STARTUP_LOGS_ENABLED = 'DD_TRACE_STARTUP_LOGS'
        end

        module Metrics
          ENV_DEFAULT_PORT = 'DD_METRIC_AGENT_PORT'
        end

        module Transport
          ENV_DEFAULT_HOST = 'DD_AGENT_HOST'
        end
      end
    end
  end
end
