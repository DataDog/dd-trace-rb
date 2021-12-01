# typed: true
require 'datadog/ci/trace_flush'

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace components
      module Components
        def initialize(settings)
          # Activate CI mode if enabled
          activate_ci_mode!(settings) if settings.ci_mode.enabled

          # Initialize normally
          super
        end

        def activate_ci_mode!(settings)
          # Activate underlying tracing test mode
          settings.test_mode.enabled = true
        end
      end
    end
  end
end
