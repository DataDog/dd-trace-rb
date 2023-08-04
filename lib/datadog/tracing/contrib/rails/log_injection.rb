module Datadog
  module Tracing
    module Contrib
      # Instrument Rails.
      module Rails
        # Rails log injection helper methods
        module LogInjection
          module_function

          # Use `app.config.log_tags` to inject propagation tags into the default Rails logger.
          def configure_log_tags(app)
            return if defined?(::SemanticLogger) && app.cofig.logger.is_a?(::SemanticLogger::Logger)

            app.config.log_tags ||= [] # Can be nil, we initialized it if so
            app.config.log_tags << proc { Tracing.log_correlation if Datadog.configuration.tracing.log_injection }
          rescue StandardError => e
            Datadog.logger.warn(
              "Unable to add Datadog Trace context to ActiveSupport::TaggedLogging: #{e.class.name} #{e.message}"
            )
            false
          end
        end
      end
    end
  end
end
