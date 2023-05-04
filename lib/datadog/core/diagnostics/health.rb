# frozen_string_literal: true

require_relative '../metrics/client'
require_relative '../../tracing/diagnostics/health'

module Datadog
  module Core
    module Diagnostics
      # Health-related diagnostics
      module Health
        # Health metrics for diagnostics
        class Metrics < Core::Metrics::Client
          extend Core::Dependency

          setting(:enabled, 'diagnostics.health_metrics.enabled')
          setting(:statsd, 'diagnostics.health_metrics.statsd') # DEV: Should be its own component.
          component_name(:health_metrics)
          # TODO: Don't reference this. Have tracing add its metrics behavior.
          extend Tracing::Diagnostics::Health::Metrics
        end
      end
    end
  end
end
