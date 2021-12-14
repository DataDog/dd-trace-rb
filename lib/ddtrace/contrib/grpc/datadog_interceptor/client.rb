# typed: ignore
require 'ddtrace/ext/http'
require 'ddtrace/ext/metadata'
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
              service: service_name, # Maintain client-side service name configuration
              resource: format_resource(keywords[:method])
            }

            tracer.trace(Ext::SPAN_CLIENT, **options) do |span, trace|
              annotate!(trace, span, keywords[:metadata], keywords[:call])

              yield
            end
          end

          private

          def annotate!(trace, span, metadata, call)
            span.set_tags(metadata)

            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_CLIENT)

            # Tag as an external peer service
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_SERVICE, span.service)
            host, _port = find_host_port(call)
            span.set_tag(Datadog::Ext::Metadata::TAG_PEER_HOSTNAME, host) if host

            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            Datadog::GRPCPropagator.inject!(trace, metadata)
          rescue StandardError => e
            Datadog.logger.debug("GRPC client trace failed: #{e}")
          end

          def format_resource(proto_method)
            proto_method.downcase
                        .split('/')
                        .reject(&:empty?)
                        .join('.')
          end

          def find_host_port(call)
            return unless call

            if call.respond_to?(:peer)
              peer_address = call.peer
            else
              # call is a "view" class with restricted method visibility.
              # We reach into it to find our data source anyway.
              peer_address = call.instance_variable_get(:@wrapped).peer
            end

            Utils.extract_host_port(peer_address)
          rescue => e
            Datadog.logger.debug { "Could not parse host:port from #{call}: #{e}" }
            nil
          end
        end
      end
    end
  end
end
