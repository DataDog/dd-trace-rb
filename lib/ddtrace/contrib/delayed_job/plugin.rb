require 'delayed/plugin'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/delayed_job/ext'

module Datadog
  module Contrib
    module DelayedJob
      # DelayedJob plugin that instruments invoke_job hook
      class Plugin < Delayed::Plugin
        def self.instrument(job, &block)
          return block.call(job) unless tracer && tracer.enabled

          # When DelayedJob is used through ActiveJob, we need to parse the payload differentely
          # to get the actual job name
          job_name = if job.payload_object.respond_to?(:job_data)
                       job.payload_object.job_data['job_class']
                     else
                       job.name
                     end

          tracer.trace(Ext::SPAN_JOB, service: configuration[:service_name], resource: job_name) do |span|
            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            span.set_tag(Ext::TAG_ID, job.id)
            span.set_tag(Ext::TAG_QUEUE, job.queue) if job.queue
            span.set_tag(Ext::TAG_PRIORITY, job.priority)
            span.set_tag(Ext::TAG_ATTEMPTS, job.attempts)
            span.span_type = Datadog::Ext::AppTypes::WORKER

            yield job
          end
        end

        def self.flush(worker, &block)
          yield worker

          tracer.shutdown! if tracer && tracer.enabled
        end

        def self.configuration
          Datadog.configuration[:delayed_job]
        end

        def self.tracer
          configuration[:tracer]
        end

        callbacks do |lifecycle|
          lifecycle.around(:invoke_job, &method(:instrument))
          lifecycle.around(:execute, &method(:flush))
        end
      end
    end
  end
end
