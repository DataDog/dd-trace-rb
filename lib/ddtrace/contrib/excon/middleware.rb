require 'excon'
require 'ddtrace/ext/http'
require 'ddtrace/ext/net'
require 'ddtrace/ext/distributed'

module Datadog
  module Contrib
    module Excon
      # Middleware implements an excon-middleware for ddtrace instrumentation
      class Middleware < ::Excon::Middleware::Base
        DEFAULT_ERROR_HANDLER = lambda do |response|
          Ext::HTTP::ERROR_RANGE.cover?(response[:status])
        end

        def initialize(app)
          super(app)
        end

        def request_call(datum)
          unless datum.key? :ddtrace_span
            span = dd_pin.tracer.trace(SERVICE)
            datum[:ddtrace_span] = span
            annotate!(span, datum)
            propagate!(span, datum) if Datadog.configuration[:excon][:distributed_tracing_enabled]
          end

          @stack.request_call(datum)
        end

        def response_call(datum)
          datum = @stack.response_call(datum)
          handle_response(datum)
          datum
        end

        def error_call(datum)
          datum = @stack.response_call(datum)
          handle_response(datum)
          datum
        end

        private

        attr_reader :app

        def annotate!(span, datum)
          span.resource = datum[:method].to_s.upcase
          span.service = service_name(datum)
          span.span_type = Ext::HTTP::TYPE
          span.set_tag(Ext::HTTP::URL, datum[:path])
          span.set_tag(Ext::HTTP::METHOD, datum[:method].to_s.upcase)
          span.set_tag(Ext::NET::TARGET_HOST, datum[:host])
          span.set_tag(Ext::NET::TARGET_PORT, datum[:port].to_s)
        end

        def handle_response(datum)
          if datum.key?(:ddtrace_span)
            span = datum[:ddtrace_span]

            if datum.key?(:response)
              response = datum[:response]
              if (Datadog.configuration[:excon][:error_handler] || DEFAULT_ERROR_HANDLER).call(response)
                span.set_error(["Error #{response[:status]}", response[:body]])
              end
              span.set_tag(Ext::HTTP::STATUS_CODE, response[:status])
            end

            span.set_error(datum[:error]) if datum.key? :error

            span.finish
            datum.delete :ddtrace_span
          end
        end

        def propagate!(span, datum)
          datum[:headers].merge!(
            Ext::DistributedTracing::HTTP_HEADER_TRACE_ID => span.trace_id,
            Ext::DistributedTracing::HTTP_HEADER_PARENT_ID => span.span_id
          )
        end

        def dd_pin
          Pin.get_from(::Excon)
        end

        def service_name(datum)
          return datum[:host] if Datadog.configuration[:excon][:split_by_domain]

          dd_pin.service
        end
      end
    end
  end
end
