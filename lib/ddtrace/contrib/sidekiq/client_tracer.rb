require 'ddtrace/contrib/sidekiq/tracing'

module Datadog
  module Contrib
    module Sidekiq
      # Tracer is a Sidekiq client-side middleware which traces job enqueues/pushes
      class ClientTracer
        include Tracing

        def initialize(options = {})
          super
          @sidekiq_service = options[:client_service_name] || Datadog.configuration[:sidekiq][:client_service_name]
        end

        # Client middleware arguments are documented here:
        #   https://github.com/mperham/sidekiq/wiki/Middleware#client-middleware
        def call(worker_class, job, queue, redis_pool)
          service = @sidekiq_service
          set_service_info(service)

          resource = job_resource(job)

          @tracer.trace(Ext::SPAN_PUSH, service: service) do |span|
            span.resource = resource
            span.set_tag(Ext::TAG_JOB_ID, job['jid'])
            span.set_tag(Ext::TAG_JOB_QUEUE, job['queue'])
            span.set_tag(Ext::TAG_JOB_WRAPPER, job['class']) if job['wrapped']

            yield
          end
        end
      end
    end
  end
end
