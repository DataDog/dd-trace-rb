module Datadog
  module Contrib
    # Instrument Rails.
    module Rails
      # Rails log injection helper methods
      module LogInjection
        module_function

        def add_lograge_logger(app)
          # custom_options defaults to nil and can be either a hash or a lambda which returns a hash
          # https://github.com/roidrage/lograge/blob/1729eab7956bb95c5992e4adab251e4f93ff9280/lib/lograge.rb#L28
          if (custom_options = app.config.lograge.custom_options).nil?
            # if it's not set, we set to a lambda that returns DD tracing context
            app.config.lograge.custom_options = lambda do |_event|
              # Retrieves trace information for current thread
              correlation = Datadog.tracer.active_correlation

              datadog_trace_log_hash(correlation)
            end
          # check if lambda, if so then define a new lambda which invokes the original lambda and
          # merges the returned hash with the the DD tracing context hash.
          elsif custom_options.respond_to?(:call)
            app.config.lograge.custom_options = lambda do |event|
              # invoke original lambda
              result = custom_options.call(event)
              # Retrieves trace information for current thread
              correlation = Datadog.tracer.active_correlation
              # merge original lambda with datadog context
              result.merge(datadog_trace_log_hash(correlation))
            end
          # otherwise if it's just a static hash, we have to wrap that hash in a lambda to retrieve
          # the DD tracing context, then merge the tracing context with the original static hash.
          # don't modify if custom_options is not an accepted format.
          elsif custom_options.is_a?(Hash)
            app.config.lograge.custom_options = lambda do |_event|
              # Retrieves trace information for current thread
              correlation = Datadog.tracer.active_correlation

              # merge original lambda with datadog context
              custom_options.merge(datadog_trace_log_hash(correlation))
            end
          end
        rescue StandardError => e
          # TODO: can we use Datadog.logger at this point?
          Datadog.logger.warn("Unable to add Datadog Trace context to Lograge: #{e.message}")
          false
        end

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
