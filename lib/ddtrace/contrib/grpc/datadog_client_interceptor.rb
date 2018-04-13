require 'grpc'
require 'ddtrace/ext/grpc'
require 'ddtrace/propagation/grpc_propagator'

module Datadog
  module Contrib
    module GRPC
      # The DatadogClientIntercptor implements the basic interface
      # for gRPC middleware. When you declare Datadog usage of the gRPC
      # module, the interceptor must be explicitly declared for usage.
      class DatadogClientInterceptor < ::GRPC::ClientInterceptor
        def request_response(request: nil, call: nil, method: nil, metadata: nil)
          trace_client(method, metadata) { yield }
        end

        def client_streamer(requests: nil, call: nil, method: nil, metadata: nil)
          trace_client(method, metadata) { yield }
        end

        def server_streamer(request: nil, call: nil, method: nil, metadata: nil)
          trace_client(method, metadata) { yield }
        end

        def bidi_streamer(requests: nil, call: nil, method: nil, metadata: nil)
          trace_client(method, metadata) { yield }
        end

        private

        def datadog_pin
          @datadog_pin ||= Datadog::Pin.get_from(self.class)
        end

        def ddtracer
          datadog_pin.tracer
        end

        def trace_client(proto_method, metadata = {})
          tracer_options = {
            span_type: Datadog::Ext::GRPC::TYPE,
            service: datadog_pin.service_name,
            resource: format_proto_method(proto_method)
          }
          ddtracer.trace('grcp.client', tracer_options) do |span|
            metadata.each { |header, value| span.set_tag(header, value) }
            Datadog::GRPCPropagator.inject!(span.context, metadata)

            yield
          end
        end

        def format_proto_method(proto_method)
          proto_method.downcase
                      .split('/')
                      .reject(&:empty?)
                      .join('.')
        end
      end
    end
  end
end
