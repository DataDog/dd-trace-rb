require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module Shoryuken
      # Tracer is a Shoryuken server-side middleware which traces executed jobs
      class Tracer
        include Contrib::Instrumentation

        def base_configuration
          Datadog.configuration[:shoryuken]
        end

        def initialize(options = {})
          merge_with_configuration!(options)
        end

        def call(worker_instance, queue, sqs_msg, body)
          trace(Ext::SPAN_JOB, span_type: Datadog::Ext::AppTypes::WORKER) do |span|
            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end
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
      end
    end
  end
end
