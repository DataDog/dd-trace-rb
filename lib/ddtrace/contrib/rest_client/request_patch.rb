require 'ddtrace/ext/net'

module Datadog
  module Contrib
    module RestClient
      # RestClient RequestPatch
      module RequestPatch
        REQUEST_TRACE_NAME = 'rest_client.request'.freeze

        def self.included(base)
          base.prepend(InstanceMethods)
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def execute(&block)
            datadog_trace_request { super(&block) }
          end

          protected

          def datadog_tag_request(span)
            span.resource = method.to_s.upcase
            span.span_type = Ext::HTTP::TYPE
            span.set_tag(Ext::HTTP::URL, uri.path)
            span.set_tag(Ext::HTTP::METHOD, method.to_s.upcase)
            span.set_tag(Ext::NET::TARGET_HOST, uri.host)
            span.set_tag(Ext::NET::TARGET_PORT, uri.port)
          end

          def datadog_trace_request
            span = datadog_pin.tracer.trace(REQUEST_TRACE_NAME, service: datadog_pin.service_name)

            datadog_tag_request(span)

            response = yield span

            span.set_tag(Ext::HTTP::STATUS_CODE, response.code)
            response
          rescue ::RestClient::ExceptionWithResponse => e
            span.set_error(e) if Ext::HTTP::ERROR_RANGE.cover?(e.http_code)
            span.set_tag(Ext::HTTP::STATUS_CODE, e.http_code)

            raise e
            # rubocop:disable Lint/RescueException
          rescue Exception => e
            # rubocop:enable Lint/RescueException
            span.set_error(e)

            raise e
          ensure
            span.finish
          end

          def datadog_pin
            @datadog_pin ||= begin
              service = Datadog.configuration[:rest_client][:service_name]
              tracer = Datadog.configuration[:rest_client][:tracer]

              Datadog::Pin.new(service, app: Patcher::NAME, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
            end
          end
        end
      end
    end
  end
end
