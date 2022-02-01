# typed: true
require 'datadog/ci/flush'

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

          # Choose user defined TraceFlush or default to CI TraceFlush
          settings.test_mode.trace_flush = settings.ci_mode.trace_flush \
                                             || CI::Flush::Finished.new

          # Pass through any other options
          settings.test_mode.writer_options = settings.ci_mode.writer_options
        end
      end
    end
  end
end
