# frozen_string_literal: true

require_relative "generate_metrics"

module Datadog
  module Core
    module Telemetry
      module Event
        class Distributions < GenerateMetrics
          def type
            "distributions"
          end
        end
      end
    end
  end
end
