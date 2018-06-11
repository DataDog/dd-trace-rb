require 'delayed/plugin'

module Datadog
  module Contrib
    module DelayedJob
      class Plugin < Delayed::Plugin
        def self.instrument(worker, job, &block)
          pin = Pin.get_from(::Delayed::Worker)

          return block.call(worker, job) unless pin && pin.tracer

          pin.tracer.trace('delayed_job', service: pin.service, resource: job.name) do |span|
            span.set_tag('delayed_job.id', job.id)
            span.set_tag('delayed_job.queue', job.queue) if job.queue
            span.set_tag('delayed_job.priority', job.priority)
            span.set_tag('delayed_job.attempts', job.attempts)
            span.span_type = pin.app_type

            block.call(worker, job)
          end
        end

        callbacks do |lifecycle|
          lifecycle.around(:perform, &method(:instrument))
        end
      end
    end
  end
end
