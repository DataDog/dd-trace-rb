require 'datadog/ci/context_flush'

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

          # Choose user defined ContextFlush or default to CI ContextFlush
          settings.test_mode.context_flush = settings.ci_mode.context_flush \
                                             || Datadog::CI::ContextFlush::Finished.new

          # Pass through any other options
          settings.test_mode.writer_options = settings.ci_mode.writer_options
        end
      end
    end
  end
end
