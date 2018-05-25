require 'delayed/plugin'

module Datadog
  module Contrib
    module DelayedJob
      class Plugin < Delayed::Plugin
        def self.instrument(worker, job, &block)
          pin = Pin.get_from(::Delayed::Worker)

          return block.call(worker, job) unless pin && pin.tracer

          pin.tracer.trace('delayed.job', service: pin.service) do |span|
            span.resource = job.name
            span.set_tag('delayed.job.id', job.id)
            span.set_tag('delayed.job.queue', job.queue) if job.queue
            span.set_tag('delayed.job.priority', job.priority)
            span.set_tag('delayed.job.attempts', job.attempts)
            span.span_type = pin.app_type

            block.call(worker, job)

            span.service = pin.service
          end
        end

        callbacks do |lifecycle|
          lifecycle.around(:perform, &method(:instrument))
        end
      end
    end
  end
end
