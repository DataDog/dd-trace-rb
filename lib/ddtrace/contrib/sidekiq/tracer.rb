
require 'sidekiq/api'

require 'ddtrace/ext/app_types'

sidekiq_vs = Gem::Version.new(Sidekiq::VERSION)
sidekiq_min_vs = Gem::Version.new('4.0.0')
if sidekiq_vs < sidekiq_min_vs
  raise "sidekiq version #{sidekiq_vs} is not supported yet " \
        + "(supporting versions >=#{sidekiq_min_vs})"
end

Datadog::Tracer.log.info("activating instrumentation for sidekiq #{sidekiq_vs}")

module Datadog
  module Contrib
    module Sidekiq
      # Middleware is a Sidekiq server-side middleware which traces executed
      # jobs.
      class Tracer
        def initialize(options)
          @enabled = options.fetch(:enabled, true)
          @default_service = options.fetch(:default_service, 'sidekiq')
          @tracer = options.fetch(:tracer, Datadog.tracer)
          @debug = options.fetch(:debug, false)
          @trace_agent_hostname = options.fetch(:trace_agent_hostname,
                                                Datadog::Writer::HOSTNAME)
          @trace_agent_port = options.fetch(:trace_agent_port,
                                            Datadog::Writer::PORT)

          Datadog::Tracer.debug_logging = @debug

          @tracer.enabled = @enabled
          @tracer.set_service_info(@default_service, 'sidekiq',
                                   Datadog::Ext::AppTypes::WORKER)
        end

        def call(worker, job, queue)
          return yield unless @enabled

          @tracer.trace('sidekiq.job',
                        service: @default_service, span_type: 'job') do |span|
            span.resource = job['class']
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
