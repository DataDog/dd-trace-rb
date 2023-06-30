module Datadog
  module Tracing
    module Contrib
      # Instrument Rails.
      module Rails
        # Rails log injection helper methods
        module LogInjection
          module_function

          def set_mutatable_default(app)
            app.config.log_tags = Array(app.config.log_tags)
          end

          def append_datadog_correlation_tags(app)
            app.config.log_tags << proc { Tracing.log_correlation }
          rescue StandardError => e
            # TODO: can we use Datadog.logger at this point?
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
