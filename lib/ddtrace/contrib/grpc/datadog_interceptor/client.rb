require 'ddtrace/ext/http'
require 'ddtrace/ext/integration'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/grpc/ext'

module Datadog
  module Contrib
    module GRPC
      module DatadogInterceptor
        # The DatadogInterceptor::Client implements the tracing strategy
        # for gRPC client-side endpoints. This middleware component will
        # inject trace context information into gRPC metadata prior to
        # sending the request to the server.
        class Client < Base
          def trace(keywords)
            keywords[:metadata] ||= {}

            options = {
              span_type: Datadog::Ext::HTTP::TYPE_OUTBOUND,
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
            span.set_tags(metadata)

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE, span.service)

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            Datadog::GRPCPropagator
              .inject!(span.context, metadata)
          rescue StandardError => e
            Datadog.logger.debug("GRPC client trace failed: #{e}")
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
