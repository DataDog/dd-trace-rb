require 'grpc'
require 'ddtrace/ext/grpc'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/grpc_propagator'

module Datadog
  module Contrib
    module GRPC
      # The DatadogServerIntercptor implements the basic interface
      # for gRPC middleware. When you declare Datadog usage of the gRPC
      # module, the interceptor must be explicitly declared for usage.
      class DatadogServerInterceptor < ::GRPC::ServerInterceptor
        def request_response(request: nil, call: nil, method: nil)
          trace_server(method.name, call.metadata) { yield }
        end

        def client_streamer(call: nil, method: nil)
          trace_server(method.name, call.metadata) { yield }
        end

        def server_streamer(request: nil, call: nil, method: nil)
          trace_server(method.name, call.metadata) { yield }
        end

        def bidi_streamer(requests: nil, call: nil, method: nil)
          trace_server(method.name, call.metadata) { yield }
        end

        private

        def trace_server(proto_method_name, metadata = {})
          ddtracer = Datadog.configuration[:grpc][:tracer]
          tracer_options = {
            service: Datadog.configuration[:grpc][:service_name],
            span_type: Datadog::Ext::GRPC::TYPE,
            resource: "server.#{proto_method_name}"
          }
          ddtracer.provider.context = Datadog::GRPCPropagator.extract(metadata)
          ddtracer.trace('grcp.server', tracer_options) do |span|
            metadata.each do |header, value|
              span.set_tag(header, value) unless reserved_headers.include?(header)
            end

            yield
          end
        end

        def reserved_headers
          [
            Datadog::Ext::DistributedTracing::GRPC_METADATA_TRACE_ID,
            Datadog::Ext::DistributedTracing::GRPC_METADATA_PARENT_ID,
            Datadog::Ext::DistributedTracing::GRPC_METADATA_SAMPLING_PRIORITY
          ]
        end
      end
    end
  end
end
