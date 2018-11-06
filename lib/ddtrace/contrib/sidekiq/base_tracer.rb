require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sidekiq/ext'

module Datadog
  module Contrib
    module Sidekiq
      class BaseTracer
        def initialize(options = {})
          @tracer = options[:tracer] || Datadog.configuration[:sidekiq][:tracer]
          @sidekiq_service = options[:service_name] || Datadog.configuration[:sidekiq][:service_name]
        end

        protected

        # If class is wrapping something else, the interesting resource info
        # is the underlying, wrapped class, and not the wrapper. This is
        # primarily to support `ActiveJob`.
        def job_resource(job)
          if job['wrapped']
            job['wrapped']
          else
            job['class']
          end
        end

        # Extract any custom tracer configuration from the worker class.
        def worker_config(worker_klass)
          if worker_klass.respond_to?(:datadog_tracer_config)
            worker_klass.datadog_tracer_config
          else
            {}
          end
        end

        def sidekiq_service(resource)
          # The resource (ie. a worker) might already be a class or it might
          # be a string class name.
          klass = if resource.is_a?(Class)
                    resource
                  else
                    begin
                      Object.const_get(resource)
                    rescue NameError
                      nil
                    end
                  end

          service = worker_config(klass).fetch(:service_name, @sidekiq_service)

          # Ensure the tracer knows about this service.
          unless @tracer.services[service]
            @tracer.set_service_info(
              service,
              Ext::APP,
              Datadog::Ext::AppTypes::WORKER
            )
          end

          service
        end
      end
    end
  end
end
