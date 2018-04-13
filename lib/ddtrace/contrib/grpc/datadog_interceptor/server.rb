module Datadog
  module Contrib
    module GRPC
      module DatadogInterceptor
        # The DatadogInterceptor::Server implements the tracing strategy
        # for gRPC server-side endpoints. When the datadog fields have been
        # added to the gRPC call metadata, this middleware component will
        # extract any client-side tracing information, attempting to associate
        # its tracing context with a parent client-side context
        class Server < Base
          def trace(keywords)
            options = {
              span_type: Datadog::Ext::GRPC::TYPE,
              service: pin.service_name,
              resource: format_resource(keywords[:method])
            }
            metadata = keywords[:call].metadata

            tracer.provider.context = Datadog::GRPCPropagator
                                      .extract(metadata)

            tracer.trace('grpc.service', options) do |span|
              metadata.each do |header, value|
                next if reserved_headers.include?(header)
                span.set_tag(header, value)
              end

              yield
            end
          end

          private

          def reserved_headers
            [Datadog::Ext::DistributedTracing::GRPC_METADATA_TRACE_ID,
             Datadog::Ext::DistributedTracing::GRPC_METADATA_PARENT_ID,
             Datadog::Ext::DistributedTracing::GRPC_METADATA_SAMPLING_PRIORITY]
          end

          def format_resource(proto_method)
            proto_method.owner
                        .to_s
                        .downcase
                        .split('::')
                        .<<(proto_method.name)
                        .join('.')
          end
        end
      end
    end
  end
end
