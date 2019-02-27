require 'ddtrace/ext/http'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/grpc/ext'

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
              span_type: Datadog::Ext::HTTP::TYPE,
              service: service_name,
              resource: format_resource(keywords[:method])
            }

            tracer.trace(Ext::SPAN_CLIENT, options) do |span|
              annotate!(span, keywords[:metadata])

              yield
            end
          end

          private

          def annotate!(span, metadata)
            metadata.each do |header, value|
              span.set_tag(header, value)
            end

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            Datadog::GRPCPropagator
              .inject!(span.context, metadata)
          rescue StandardError => e
            Datadog::Tracer.log.debug("GRPC client trace failed: #{e}")
          end

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
