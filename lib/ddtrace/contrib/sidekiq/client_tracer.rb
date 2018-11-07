require 'ddtrace/contrib/sidekiq/tracing'

module Datadog
  module Contrib
    module Sidekiq
      # Tracer is a Sidekiq client-side middleware which traces job enqueues/pushes
      class ClientTracer
        include Tracing

        # Client middleware arguments are documented here:
        #   https://github.com/mperham/sidekiq/wiki/Middleware#client-middleware
        def call(worker_class, job, queue, redis_pool)
          resource = job_resource(job)
          service = sidekiq_service(resource)

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
