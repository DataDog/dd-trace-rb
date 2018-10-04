module Datadog
  module Contrib
    module Shoryuken
      # Tracer is a Shoryuken server-side middleware which traces executed jobs
      class Tracer
        DEFAULT_CONFIG = {
          enabled: true,
          shoryuken_service: 'shoryuken',
          tracer: Datadog.tracer,
          debug: false,
          trace_agent_hostname: Datadog::Writer::HOSTNAME,
          trace_agent_port: Datadog::Writer::PORT
        }.freeze

        def initialize(options = {})
          user_config = DEFAULT_CONFIG.merge(options)
          @tracer = user_config[:tracer]
          @shoryuken_service = user_config[:shoryuken_service]

          # set Tracer status
          @tracer.enabled = user_config[:enabled]
          Datadog::Tracer.debug_logging = user_config[:debug]

          # configure the Tracer instance
          @tracer.configure(
            hostname: user_config[:trace_agent_hostname],
            port: user_config[:trace_agent_port]
          )
        end

        def call(worker_instance, queue, sqs_msg, body)
          # If class is wrapping something else, the interesting resource info
          # is the underlying, wrapped class, and not the wrapper.

          # configure Shoryuken service
          tracer_info = { resource: worker_instance.class.name }
          if worker_instance.class.name.ends_with?('ShoryukenAdapter::JobWrapper')
            tracer_info[:job_id] = body['job_id'] || body[:job_id]
            tracer_info[:resource] = body['job_class'] || body[:job_class]
            tracer_info[:wrapped] = true
          else
            tracer_info[:job_id] = worker_instance.job_id
          end
          set_service_info(@shoryuken_service)

          @tracer.trace('shoryuken.job', service: @shoryuken_service, span_type: 'job') do |span|
            span.resource = tracer_info[:resource]
            span.set_tag('shoryuken.job.id', tracer_info[:job_id])
            span.set_tag('shoryuken.job.queue', queue)
            span.set_tag('shoryuken.job.wrapped', 'true') if tracer_info[:wrapped]

            yield
          end
        end

        private

        def set_service_info(service)
          return if @tracer.services[service]
          @tracer.set_service_info(
            service,
            'shoryuken',
            Datadog::Ext::AppTypes::WORKER
          )
        end
      end
    end
  end
end
