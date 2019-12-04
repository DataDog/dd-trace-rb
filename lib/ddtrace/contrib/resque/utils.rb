module Datadog
  module Contrib
    module Resque
      module Utils
        def self.hook_wrapper(hook_name, span_name)
          Proc.new do |*args|
            pin = Datadog::Pin.get_from(::Resque)
            return super(*args) unless pin && pin.enabled?

            pin.tracer.trace(span_name, service: pin.service_name) do |span|
              span.resource = "#{self.name}.#{hook_name}"
              return super(*args)
            end
          end
        end
      end
    end
  end
end
