require 'ddtrace/contrib/analytics'
require 'resque'

module Datadog
  module Contrib
    module Resque
      module Worker
        def report_failed_job(job, exception)
          pin = Datadog::Pin.get_from(::Resque)
          return super(job, exception) unless pin && pin.enabled?

          span = pin.tracer.active_span
          return super(job, exception) unless span

          span.set_error(exception)
          super(job, exception)
        end

        def perform(job)
          pin = Datadog::Pin.get_from(::Resque)
          return super(job) unless pin && pin.enabled?

          datadog_configuration = Datadog.configuration[:resque]
          return super(job) unless datadog_configuration

          # Clear out any existing context since we forked
          # DEV: Otherwise we would inherit from any existing context in the parent process
          pin.tracer.provider.context = nil if fork_per_job?

          pin.tracer.trace(Ext::SPAN_JOB, service: pin.service_name) do |span|
            begin
              span.resource = job.payload_class_name
              span.span_type = Datadog::Ext::AppTypes::WORKER
              span.set_tag(Ext::TAG_QUEUE, job.queue)
              span.set_tag(Ext::TAG_CLASS, job.payload_class_name)

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
              end
            rescue StandardError => e
              Datadog::Tracer.log.error("Failed to setup Resque task span: #{e}")
            end

            begin
              return super(job)
            ensure
              yield job if block_given?
            end
          end
        ensure
          # Manually shutdown the tracer and wait for final flush if we were forked
          if fork_per_job?
            pin.tracer.shutdown!
            pin.tracer.writer.worker.join
          end
        end
      end
    end
  end
end
