require 'delayed/worker'

module Datadog
  module Contrib
    module DelayedJob
      # instrument Delayed::Worker methods
      module Instrumentation
        def run(job)
          pin = Pin.get_from(::Delayed::Worker)
          return super(job) unless pin && pin.tracer

          pin.tracer.trace('delayed.job', service: pin.service) do |span|
            span.resource = job.name
            span.set_tag('delayed.job.id', job.id)
            span.set_tag('delayed.job.queue', job.queue)
            span.set_tag('delayed.job.attempts', job.attempts)
            span.span_type = pin.app_type

            super(job)

            span.service = pin.service
          end
        end
      end
    end
  end
end
