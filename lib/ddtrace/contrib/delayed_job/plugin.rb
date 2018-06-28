require 'delayed/plugin'

module Datadog
  module Contrib
    module DelayedJob
      # DelayedJob plugin that instruments invoke_job hook
      class Plugin < Delayed::Plugin
        def self.instrument(job, &block)
          return block.call(job) unless tracer && tracer.enabled

          tracer.trace('delayed_job'.freeze, service: configuration[:service_name], resource: job.name) do |span|
            span.set_tag('delayed_job.id'.freeze, job.id)
            span.set_tag('delayed_job.queue'.freeze, job.queue) if job.queue
            span.set_tag('delayed_job.priority'.freeze, job.priority)
            span.set_tag('delayed_job.attempts'.freeze, job.attempts)
            span.span_type = Ext::AppTypes::WORKER

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
