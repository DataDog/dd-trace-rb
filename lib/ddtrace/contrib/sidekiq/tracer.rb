require 'sidekiq/api'

require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    module Sidekiq
      # Tracer is a Sidekiq server-side middleware which traces executed jobs
      class Tracer
        def initialize(options = {})
          config = Datadog.configuration[:sidekiq].merge(options)
          @tracer = config[:tracer]
          @sidekiq_service = config[:service_name]
        end

        def call(worker, job, queue)
          # If class is wrapping something else, the interesting resource info
          # is the underlying, wrapped class, and not the wrapper.
          resource = if job['wrapped']
                       job['wrapped']
                     else
                       job['class']
                     end

          # configure Sidekiq service
          service = sidekiq_service(resource_worker(resource))
          set_service_info(service)

          @tracer.trace('sidekiq.job', service: service, span_type: Datadog::Ext::AppTypes::WORKER) do |span|
            span.resource = resource
            span.set_tag('sidekiq.job.id', job['jid'])
            span.set_tag('sidekiq.job.retry', job['retry'])
            span.set_tag('sidekiq.job.queue', job['queue'])
            span.set_tag('sidekiq.job.wrapper', job['class']) if job['wrapped']

            yield
          end
        end

        private

        # rubocop:disable Lint/HandleExceptions
        def resource_worker(resource)
          Object.const_get(resource)
        rescue NameError
        end

        def worker_config(worker)
          if worker.respond_to?(:datadog_tracer_config)
            worker.datadog_tracer_config
          else
            {}
          end
        end

        def sidekiq_service(resource)
          worker_config(resource).fetch(:service_name, @sidekiq_service)
        end

        def set_service_info(service)
          return if @tracer.services[service]
          @tracer.set_service_info(
            service,
            'sidekiq',
            Datadog::Ext::AppTypes::WORKER
          )
        end
      end
    end
  end
end
