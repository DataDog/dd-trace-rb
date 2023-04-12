module Datadog
  module Tracing
    module Contrib
      # Instrument Rails.
      module Rails
        # Rails log injection helper methods
        module LogInjection
          module_function

          def add_as_tagged_logging_logger(app)
            # we want to check if the current logger is a tagger logger instance
            # log_tags defaults to nil so we have to set as an array if nothing exists yet
            if (log_tags = app.config.log_tags).nil?
              app.config.log_tags = [proc { Tracing.log_correlation }]
            # if existing log_tags configuration exists, append to the end of the array
            elsif log_tags.is_a?(Array)
              app.config.log_tags << proc { Tracing.log_correlation }
            end
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
