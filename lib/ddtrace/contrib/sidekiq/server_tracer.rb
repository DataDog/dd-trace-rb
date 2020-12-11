require 'ddtrace/contrib/sidekiq/tracing'
require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module Sidekiq
      # Tracer is a Sidekiq server-side middleware which traces executed jobs
      class ServerTracer
        include Tracing

        def initialize(options = {})
          super
          @sidekiq_service = options[:service_name] || configuration[:service_name]
          @error_handler = options[:error_handler] || configuration[:error_handler]
        end

        def call(worker, job, queue)
          resource = job_resource(job)

          service = worker_config(resource, :service_name) || @sidekiq_service
          tag_args = worker_config(resource, :tag_args) || configuration[:tag_args]

          @tracer.trace(Ext::SPAN_JOB, service: service, span_type: Datadog::Ext::AppTypes::WORKER,
                                       on_error: @error_handler) do |span|

            span.resource = resource
            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            span.set_tag(Ext::TAG_JOB_ID, job['jid'])
            span.set_tag(Ext::TAG_JOB_RETRY, job['retry'])
            span.set_tag(Ext::TAG_JOB_RETRY_COUNT, job['retry_count'])
            span.set_tag(Ext::TAG_JOB_QUEUE, job['queue'])
            span.set_tag(Ext::TAG_JOB_WRAPPER, job['class']) if job['wrapped']
            span.set_tag(Ext::TAG_JOB_DELAY, 1000.0 * (Time.now.utc.to_f - job['enqueued_at'].to_f))
            if tag_args && !job['args'].nil? && !job['args'].empty?
              span.set_tag(Ext::TAG_JOB_ARGS, job['args'])
            end

            yield
          end
        end

        private

        def configuration
          Datadog.configuration[:sidekiq]
        end

        def worker_config(resource, key)
          # Try to get the Ruby class from the resource name.
          worker_klass = begin
            Object.const_get(resource)
          rescue NameError
            nil
          end

          if worker_klass.respond_to?(:datadog_tracer_config)
            worker_klass.datadog_tracer_config[key]
          end
        end
      end
    end
  end
end
