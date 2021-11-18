# typed: ignore
require 'delayed/plugin'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/delayed_job/ext'

module Datadog
  module Contrib
    module DelayedJob
      # DelayedJob plugin that instruments invoke_job hook
      class Plugin < Delayed::Plugin
        def self.instrument_invoke(job)
          return yield(job) unless tracer && tracer.enabled

          tracer.trace(Ext::SPAN_JOB, service: configuration[:service_name], resource: job_name(job),
                                      on_error: configuration[:error_handler]) do |span|
            set_sample_rate(span)

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

        def self.instrument_enqueue(job)
          return yield(job) unless tracer && tracer.enabled

          tracer.trace(Ext::SPAN_ENQUEUE, service: configuration[:client_service_name], resource: job_name(job)) do |span|
            set_sample_rate(span)

            # Measure service stats
            Contrib::Analytics.set_measured(span)

            span.set_tag(Ext::TAG_QUEUE, job.queue) if job.queue
            span.set_tag(Ext::TAG_PRIORITY, job.priority)
            span.span_type = Datadog::Ext::AppTypes::WORKER

            yield job
          end
        end

        def self.flush(worker)
          yield worker

          tracer.shutdown! if tracer && tracer.enabled
        end

        def self.configuration
          Datadog.configuration[:delayed_job]
        end

        def self.tracer
          configuration[:tracer]
        end

        def self.job_name(job)
          # When DelayedJob is used through ActiveJob, we need to parse the payload differentely
          # to get the actual job name
          return job.payload_object.job_data['job_class'] if job.payload_object.respond_to?(:job_data)

          job.name
        end

        def self.set_sample_rate(span)
          # Set analytics sample rate
          if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
            Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
          end
        end

        callbacks do |lifecycle|
          lifecycle.around(:invoke_job, &method(:instrument_invoke))
          lifecycle.around(:enqueue, &method(:instrument_enqueue))
          lifecycle.around(:execute, &method(:flush))
        end
      end
    end
  end
end
