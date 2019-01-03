require 'ddtrace/contrib/sidekiq/tracing'
require 'ddtrace/contrib/sampling'

module Datadog
  module Contrib
    module Sidekiq
      # Tracer is a Sidekiq client-side middleware which traces job enqueues/pushes
      class ClientTracer
        include Tracing

        def initialize(options = {})
          super
          @sidekiq_service = options[:client_service_name] || configuration[:client_service_name]
          set_service_info(@sidekiq_service)
        end

        # Client middleware arguments are documented here:
        #   https://github.com/mperham/sidekiq/wiki/Middleware#client-middleware
        def call(worker_class, job, queue, redis_pool)
          resource = job_resource(job)

          @tracer.trace(Ext::SPAN_PUSH, service: @sidekiq_service) do |span|
            span.resource = resource
            Contrib::Sampling.set_event_sample_rate(span, configuration[:event_sample_rate])
            span.set_tag(Ext::TAG_JOB_ID, job['jid'])
            span.set_tag(Ext::TAG_JOB_QUEUE, job['queue'])
            span.set_tag(Ext::TAG_JOB_WRAPPER, job['class']) if job['wrapped']

            yield
          end
        end

        private

        def configuration
          Datadog.configuration[:sidekiq]
        end
      end
    end
  end
end
