require_relative '../flush'

module Datadog
  module CI
    module Configuration
      # Adds CI behavior to Datadog trace components
      module Components
        def initialize(settings)
          # Activate CI mode if enabled
          activate_ci!(settings) if settings.ci.enabled

          # Initialize normally
          super
        end

        def activate_ci!(settings)
          # Activate underlying tracing test mode
          settings.tracing.test_mode.enabled = true

          # Choose user defined TraceFlush or default to CI TraceFlush
          settings.tracing.test_mode.trace_flush = settings.ci.trace_flush \
                                             || CI::Flush::Finished.new

          # Pass through any other options
          settings.tracing.test_mode.writer_options = settings.ci.writer_options
        end
      end
    end
  end
end
