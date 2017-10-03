require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    # Uses Resque job hooks to create traces
    module Resque
      module ResqueJob
        def around_perform(*args)
          pin = Pin.get_from(::Resque)
          pin.tracer.trace('resque.job', service: pin.service) do |span|
            span.resource = name
            span.span_type = pin.app_type
            yield
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
