# frozen_string_literal: true

module Datadog
  module Tracing
    module Runtime
      # Decorates runtime metrics feature
      module Metrics
        def self.associate_trace(trace)
          return unless trace && !trace.empty?

          Datadog.send(:components).runtime_metrics.register_service(trace.service) unless trace.service.nil?
        end
      end
    end
  end
end
