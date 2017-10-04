require 'ddtrace/ext/app_types'
require 'resque'

module Datadog
  module Contrib
    module Resque
      # Uses Resque job hooks to create traces
      module ResqueJob
        def around_perform(*args)
          pin = Pin.get_from(::Resque)
          pin.tracer.trace('resque.job', service: pin.service) do |span|
            span.resource = name
            span.span_type = pin.app_type
            yield
            span.service = pin.service
          end
        end

        def after_perform(*args)
          pin = Pin.get_from(::Resque)
          pin.tracer.shutdown!
        end
      end
    end
  end
end

Resque.before_first_fork do
  pin = Datadog::Pin.get_from(Resque)
  pin.tracer.set_service_info(pin.service, 'resque', Datadog::Ext::AppTypes::WORKER)
end
