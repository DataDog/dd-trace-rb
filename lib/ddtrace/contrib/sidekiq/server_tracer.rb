require 'ddtrace/contrib/sidekiq/tracing'

module Datadog
  module Contrib
    module Sidekiq
      # Tracer is a Sidekiq server-side middleware which traces executed jobs
      class ServerTracer
        include Tracing

        def call(worker, job, queue)
          resource = job_resource(job)
          service = sidekiq_service(resource)

          @tracer.trace(Ext::SPAN_JOB, service: service, span_type: Datadog::Ext::AppTypes::WORKER) do |span|
            span.resource = resource
            span.set_tag(Ext::TAG_JOB_ID, job['jid'])
            span.set_tag(Ext::TAG_JOB_RETRY, job['retry'])
            span.set_tag(Ext::TAG_JOB_QUEUE, job['queue'])
            span.set_tag(Ext::TAG_JOB_WRAPPER, job['class']) if job['wrapped']
            span.set_tag(Ext::TAG_JOB_DELAY, 1000.0 * (Time.now.utc.to_f - job['enqueued_at'].to_f))

            yield
          end
        end
      end
    end
  end
end
