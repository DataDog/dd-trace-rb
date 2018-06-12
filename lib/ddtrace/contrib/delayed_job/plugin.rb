require 'delayed/plugin'

module Datadog
  module Contrib
    module DelayedJob
      class Plugin < Delayed::Plugin
        def self.instrument(job, &block)
          pin = Pin.get_from(::Delayed::Worker)

          return block.call(job) unless pin && pin.tracer

          pin.tracer.trace('delayed_job'.freeze, service: pin.service, resource: job.name) do |span|
            span.set_tag('delayed_job.id'.freeze, job.id)
            span.set_tag('delayed_job.queue'.freeze, job.queue) if job.queue
            span.set_tag('delayed_job.priority'.freeze, job.priority)
            span.set_tag('delayed_job.attempts'.freeze, job.attempts)
            span.span_type = pin.app_type

            block.call(job)
          end
        end

        callbacks do |lifecycle|
          lifecycle.around(:invoke_job, &method(:instrument))
        end
      end
    end
  end
end
