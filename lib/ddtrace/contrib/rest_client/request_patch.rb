module Datadog
  module Contrib
    module RestClient
      # RestClient RequestPatch
      module RequestPatch
        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def execute(&block)
            datadog_pin.tracer.trace('rest_client') do |span|
              super
            end
          end

          def datadog_pin
            @datadog_pin ||= begin
              service = Datadog.configuration[:rest_client][:service_name]
              tracer = Datadog.configuration[:rest_client][:tracer]

              Datadog::Pin.new(service, app: 'rest_client'.freeze, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
            end
          end
        end
      end
    end
  end
end
