require 'ddtrace/contrib/sampling'

module Datadog
  module Contrib
    module Shoryuken
      # Tracer is a Shoryuken server-side middleware which traces executed jobs
      class Tracer
        def initialize(options = {})
          @tracer = options[:tracer] || configuration[:tracer]
          @shoryuken_service = options[:service_name] || configuration[:service_name]
          set_service_info(@shoryuken_service)
        end

        def call(worker_instance, queue, sqs_msg, body)
          @tracer.trace(Ext::SPAN_JOB, service: @shoryuken_service, span_type: Datadog::Ext::AppTypes::WORKER) do |span|
            span.resource = worker_instance.class.name
            Contrib::Sampling.set_event_sample_rate(span, configuration[:event_sample_rate])
            span.set_tag(Ext::TAG_JOB_ID, sqs_msg.message_id)
            span.set_tag(Ext::TAG_JOB_QUEUE, queue)
            span.set_tag(Ext::TAG_JOB_ATTRIBUTES, sqs_msg.attributes) if sqs_msg.respond_to?(:attributes)
            span.set_tag(Ext::TAG_JOB_BODY, body)

            yield
          end
        end

        private

        def configuration
          Datadog.configuration[:shoryuken]
        end

        def set_service_info(service)
          return if @tracer.nil? || @tracer.services[service]
          @tracer.set_service_info(
            service,
            Ext::APP,
            Datadog::Ext::AppTypes::WORKER
          )
        end
      end
    end
  end
end
