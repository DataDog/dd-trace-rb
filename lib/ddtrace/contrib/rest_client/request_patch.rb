require 'ddtrace/ext/net'

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
            datadog_pin.tracer.trace('rest_client.request'.freeze, service: datadog_pin.service_name) do |span|
              span.resource = method.to_s.upcase
              span.span_type = Ext::HTTP::TYPE
              span.set_tag(Ext::HTTP::URL, uri.path)
              span.set_tag(Ext::HTTP::METHOD, method.to_s.upcase)
              span.set_tag(Ext::NET::TARGET_HOST, uri.host)
              span.set_tag(Ext::NET::TARGET_PORT, uri.port)

              datadog_tag_response_code(span) { super(&block) }
            end
          end

          protected

          def datadog_pin
            @datadog_pin ||= begin
              service = Datadog.configuration[:rest_client][:service_name]
              tracer = Datadog.configuration[:rest_client][:tracer]

              Datadog::Pin.new(service, app: 'rest_client'.freeze, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
            end
          end

          def datadog_tag_response_code(span)
            response = yield
            span.set_tag(Ext::HTTP::STATUS_CODE, response.code)

            response
          rescue ::RestClient::ExceptionWithResponse => e
            span.set_tag(Ext::HTTP::STATUS_CODE, e.http_code)

            raise e
          end
        end
      end
    end
  end
end
