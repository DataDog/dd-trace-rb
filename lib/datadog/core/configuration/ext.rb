# typed: true

module Datadog
  module Core
    module Configuration
      module Ext
        # @public_api
        module Diagnostics
          ENV_DEBUG_ENABLED = 'DD_TRACE_DEBUG'.freeze
          ENV_HEALTH_METRICS_ENABLED = 'DD_HEALTH_METRICS_ENABLED'.freeze
          ENV_STARTUP_LOGS_ENABLED = 'DD_TRACE_STARTUP_LOGS'.freeze
        end
      end
    end
  end
end
