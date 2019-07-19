require 'ddtrace/contrib/roda/ext'
require 'ddtrace/contrib/analytics'

module Datadog
  module Contrib
    module Roda
      module Instrumentation
        def datadog_pin
          @datadog_pin ||= begin
            service = Datadog.configuration[:roda][:service_name]
            tracer = Datadog.configuration[:roda][:tracer]

            Datadog::Pin.new(service, app: Ext::APP, app_type: Datadog::Ext::AppTypes::WEB, tracer: tracer)
          end
        end

        def _roda_handle_main_route
          instrument(Ext::SPAN_REQUEST) { super }
        end

        def call
          instrument(Ext::SPAN_REQUEST) { super }
        end

        private

        def instrument(span_name, &block)
          pin = datadog_pin
          return yield unless pin && pin.tracer

          set_distributed_tracing_context!(request.env)

          pin.tracer.trace(span_name) do |span|
            begin
              request_method = request.request_method.to_s.upcase

              span.service = pin.service
              span.span_type = Datadog::Ext::HTTP::TYPE_INBOUND

              span.resource = request_method
              # Using the method as a resource, as URL/path can trigger
              # a possibly infinite number of resources.
              span.set_tag(Datadog::Ext::HTTP::URL, request.path)
              span.set_tag(Datadog::Ext::HTTP::METHOD, request_method)

              # Add analytics tag to the span
              Contrib::Analytics.set_sample_rate(span, Datadog.configuration[:roda][:analytics_sample_rate]) if Contrib::Analytics.enabled?(Datadog.configuration[:roda][:analytics_enabled])
            rescue StandardError => e
              Datadog::Tracer.log.error("error preparing span for roda request: #{e}")
            ensure
              response = yield
            end

            span.set_error(1) if response[0].to_s.start_with?('5')
            response
          end
        end

        def set_distributed_tracing_context!(env)
          if Datadog.configuration[:roda][:distributed_tracing] && Datadog.configuration[:roda][:tracer].provider.context.trace_id.nil?
            context = HTTPPropagator.extract(env)
            Datadog.configuration[:roda][:tracer].provider.context = context if context && context.trace_id
          end
        end
      end
    end
  end
end
