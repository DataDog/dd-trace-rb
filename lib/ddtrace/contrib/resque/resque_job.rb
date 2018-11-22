require 'ddtrace/ext/app_types'
require 'ddtrace/sync_writer'
require 'ddtrace/contrib/sidekiq/ext'
require 'resque'

module Datadog
  module Contrib
    module Resque
      # Uses Resque job hooks to create traces
      module ResqueJob
        def around_perform(*_)
          pin = Pin.get_from(::Resque)
          return yield unless pin && pin.tracer
          pin.tracer.trace(Ext::SPAN_JOB, service: pin.service) do |span|
            span.resource = name
            span.span_type = pin.app_type
            yield
            span.service = pin.service
          end
        end

        def after_perform_shutdown_tracer(*_)
          shutdown_tracer_when_forked!
        end

        def on_failure_shutdown_tracer(*_)
          shutdown_tracer_when_forked!
        end

        def shutdown_tracer_when_forked!
          pin = Datadog::Pin.get_from(Resque)
          pin.tracer.shutdown! if pin && pin.tracer && pin.config[:forked]
        end
      end
    end
  end
end

Resque.after_fork do
  # get the current tracer
  pin = Datadog::Pin.get_from(Resque)
  next unless pin && pin.tracer
  pin.config ||= {}
  pin.config[:forked] = true

  # clean the state so no CoW happens
  pin.tracer.provider.context = nil
end
