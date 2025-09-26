# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        # Active Job log injection wrapped around job execution
        module LogInjection
          def perform_now
            if Datadog.configuration.tracing.log_injection && logger.respond_to?(:tagged)
              logger.tagged(Tracing.log_correlation) { super }
            else
              super
            end
          end
        end
      end
    end
  end
end
