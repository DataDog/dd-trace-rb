module Datadog
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
            app.config.log_tags = [proc { Datadog.tracer.active_correlation.to_s }]
          # if existing log_tags configuration exists, append to the end of the array
          elsif log_tags.is_a?(Array)
            app.config.log_tags << proc { Datadog.tracer.active_correlation.to_s }
          end
        rescue StandardError => e
          # TODO: can we use Datadog.logger at this point?
          Datadog.logger.warn("Unable to add Datadog Trace context to ActiveSupport::TaggedLogging: #{e.message}")
          false
        end

        def datadog_trace_log_hash(correlation)
          {
            # Adds IDs as tags to log output
            dd: {
              # To preserve precision during JSON serialization, use strings for large numbers
              trace_id: correlation.trace_id.to_s,
              span_id: correlation.span_id.to_s,
              env: correlation.env.to_s,
              service: correlation.service.to_s,
              version: correlation.version.to_s
            },
            ddsource: ['ruby']
          }
        end
      end
    end
  end
end
