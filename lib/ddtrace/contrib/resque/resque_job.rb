require 'ddtrace/ext/app_types'
require 'ddtrace/sync_writer'
require 'ddtrace/contrib/sidekiq/ext'
require 'resque'

module Datadog
  module Contrib
    module Resque
      # Uses Resque job hooks to create traces
      module ResqueJob
        def around_perform(*args)
          pin = Pin.get_from(::Resque)
          return yield unless pin && pin.tracer
          pin.tracer.trace(Ext::SPAN_JOB, service: pin.service) do |span|
            span.resource = name
            span.span_type = pin.app_type
            yield
            span.service = pin.service
          end
        end

        def on_failure_datadog_shutdown!(*args)
          datadog_shutdown!
        end

        def after_perform_datadog_shutdown!(*args)
          datadog_shutdown!
        end

        def datadog_shutdown!
          pin = Pin.get_from(::Resque)
          pin.tracer.shutdown! if pin && pin.tracer
        end
      end
    end
  end
end

Resque.before_first_fork do
  Datadog::Contrib::Resque.sync_writer = nil

  pin = Datadog::Pin.get_from(Resque)
  next unless pin && pin.tracer && Datadog.configuration[:resque][:use_sync_writer]

  # Create SyncWriter instance before forking
  Datadog::Contrib::Resque.sync_writer = if Datadog.configuration[:resque][:use_sync_writer]
                                           Datadog::SyncWriter.new(transport: pin.tracer.writer.transport)
                                         end
end

Resque.after_fork do
  # get the current tracer
  pin = Datadog::Pin.get_from(Resque)
  next unless pin && pin.tracer

  # clean the state so no CoW happens
  pin.tracer.provider.context = nil

  if Datadog::Contrib::Resque.sync_writer
    pin.tracer.writer = Datadog::Contrib::Resque.sync_writer
  end
end
