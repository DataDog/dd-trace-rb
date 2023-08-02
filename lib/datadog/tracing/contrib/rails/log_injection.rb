module Datadog
  module Tracing
    module Contrib
      # Instrument Rails.
      module Rails
        # Rails log injection helper methods
        module LogInjection
          module_function

          # Use `app.config.log_tags` to inject propagation tags into the default Rails logger.
          def configure_log_tags(app_cofig)
            # Semantic Logger's named tags override Rails built-in config.log_tags with a hash value
            return if Hash === app_cofig.log_tags

            app_cofig.log_tags ||= [] # Can be nil, we initialized it if so
            app_cofig.log_tags << proc { Tracing.log_correlation if Datadog.configuration.tracing.log_injection }
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
