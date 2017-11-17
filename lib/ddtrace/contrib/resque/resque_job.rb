require 'ddtrace/ext/app_types'
require 'ddtrace/sync_writer'
require 'resque'

module Datadog
  module Contrib
    module Resque
      # Uses Resque job hooks to create traces
      module ResqueJob
        def around_perform(*args)
          pin = Pin.get_from(::Resque)
          return yield unless pin && pin.tracer
          pin.tracer.trace('resque.job', service: pin.service) do |span|
            span.resource = name
            span.span_type = pin.app_type
            yield
            span.service = pin.service
          end
        end
      end
    end
  end
end

Resque.before_first_fork do
  pin = Datadog::Pin.get_from(Resque)
  next unless pin && pin.tracer
  pin.tracer.set_service_info(pin.service, 'resque', Datadog::Ext::AppTypes::WORKER)

  # Create SyncWriter instance before forking
  sync_writer = Datadog::SyncWriter.new(transport: pin.tracer.writer.transport)
  Datadog::SyncWriter::CACHED_INSTANCE = sync_writer
end

Resque.after_fork do
  # get the current tracer
  pin = Datadog::Pin.get_from(Resque)
  next unless pin && pin.tracer
  # clean the state so no CoW happens
  pin.tracer.provider.context = nil
  pin.tracer.writer = Datadog::SyncWriter::CACHED_INSTANCE
end
