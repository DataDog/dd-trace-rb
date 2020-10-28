require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module Shoryuken
      # Tracer is a Shoryuken server-side middleware which traces executed jobs
      class Tracer
        def initialize(options = {})
          @tracer = options[:tracer] || configuration[:tracer]
          @shoryuken_service = options[:service_name] || configuration[:service_name]
          @error_handler = options[:error_handler] || configuration[:error_handler]
        end

        def call(worker_instance, queue, sqs_msg, body)
          @tracer.trace(Ext::SPAN_JOB, service: @shoryuken_service, span_type: Datadog::Ext::AppTypes::WORKER,
                                       on_error: @error_handler) do |span|

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            span.resource = resource(worker_instance, body)
            span.set_tag(Ext::TAG_JOB_ID, sqs_msg.message_id)
            span.set_tag(Ext::TAG_JOB_QUEUE, queue)
            span.set_tag(Ext::TAG_JOB_ATTRIBUTES, sqs_msg.attributes) if sqs_msg.respond_to?(:attributes)
            span.set_tag(Ext::TAG_JOB_BODY, body)

            yield
          end
        end

        private

        def resource(worker_instance, body)
          # If it's a Hash, try to get the job class from it.
          # This is for ActiveJob compatibility.
          job_class = body['job_class'] if body.is_a?(Hash)
          # If nothing is available, use the worker class name.
          job_class || worker_instance.class.name
        end

        def configuration
          Datadog.configuration[:shoryuken]
        end
      end
    end
  end
end
