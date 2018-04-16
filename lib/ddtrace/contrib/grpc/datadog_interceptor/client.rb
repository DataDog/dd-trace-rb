module Datadog
  module Contrib
    module GRPC
      module DatadogInterceptor
        # The DatadogInterceptor::Client implements the tracing strategy
        # for gRPC client-side endpoitns. This middleware compoent will
        # inject trace context information into gRPC metadata prior to
        # sending the request to the server.
        class Client < Base
          def trace(keywords)
            keywords[:metadata] ||= {}

            options = {
              span_type: Datadog::Ext::GRPC::TYPE,
              service: datadog_pin.service_name,
              resource: format_resource(keywords[:method])
            }

            tracer.trace('grpc.client', options) do |span|
              keywords[:metadata].each do |header, value|
                span.set_tag(header, value)
              end

              Datadog::GRPCPropagator
                .inject!(span.context, keywords[:metadata])

              yield
            end
          end

          private

          def format_resource(proto_method)
            proto_method.downcase
                        .split('/')
                        .reject(&:empty?)
                        .join('.')
          end
        end
      end
    end
  end
end
