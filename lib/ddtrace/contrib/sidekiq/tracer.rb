require 'sidekiq/api'

require 'ddtrace/ext/app_types'

sidekiq_vs = Gem::Version.new(Sidekiq::VERSION)
sidekiq_min_vs = Gem::Version.new('4.0.0')
if sidekiq_vs < sidekiq_min_vs
  raise "sidekiq version #{sidekiq_vs} is not supported yet " \
        + "(supporting versions >=#{sidekiq_min_vs})"
end

Datadog::Tracer.log.debug("Activating instrumentation for Sidekiq '#{sidekiq_vs}'")

module Datadog
  module Contrib
    module Sidekiq
      DEFAULT_CONFIG = {
        enabled: true,
        sidekiq_service: 'sidekiq',
        tracer: Datadog.tracer,
        debug: false,
        trace_agent_hostname: Datadog::Writer::HOSTNAME,
        trace_agent_port: Datadog::Writer::PORT
      }.freeze

      # Middleware is a Sidekiq server-side middleware which traces executed jobs
      class Tracer
        def initialize(options = {})
          # check if Rails configuration is available and use it to override
          # Sidekiq defaults
          rails_config = ::Rails.configuration.datadog_trace rescue {}
          base_config = DEFAULT_CONFIG.merge(rails_config)
          user_config = base_config.merge(options)
          @tracer = user_config[:tracer]
          @sidekiq_service = user_config[:sidekiq_service]

          # set Tracer status
          @tracer.enabled = user_config[:enabled]
          Datadog::Tracer.debug_logging = user_config[:debug]

          # configure the Tracer instance
          @tracer.configure(
            hostname: user_config[:trace_agent_hostname],
            port: user_config[:trace_agent_port]
          )

          # configure Sidekiq service
          @tracer.set_service_info(
            @sidekiq_service,
            'sidekiq',
            Datadog::Ext::AppTypes::WORKER
          )
        end

        def call(worker, job, queue)
          @tracer.trace('sidekiq.job', service: @sidekiq_service, span_type: 'job') do |span|
            if job['wrapped']
              # If class is wrapping something else, the interesting resource info
              # is the underlying, wrapped class, and not the wrapper.
              span.resource = job['wrapped']
              span.set_tag('sidekiq.job.wrapper', job['class'])
            else
              span.resource = job['class']
            end
            span.set_tag('sidekiq.job.id', job['jid'])
            span.set_tag('sidekiq.job.retry', job['retry'])
            span.set_tag('sidekiq.job.queue', job['queue'])
            yield
          end
        end
      end
    end
  end
end
