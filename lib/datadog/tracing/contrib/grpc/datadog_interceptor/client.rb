# typed: ignore
require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/grpc/ext'

module Datadog
  module Tracing
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
                span_type: Tracing::Metadata::Ext::HTTP::TYPE_OUTBOUND,
                service: service_name, # Maintain client-side service name configuration
                resource: format_resource(keywords[:method])
              }

              Tracing.trace(Ext::SPAN_CLIENT, **options) do |span, trace|
                annotate!(trace, span, keywords[:metadata], keywords[:call])

                yield
              end
            end

            private

            def annotate!(trace, span, metadata, call)
              span.set_tags(metadata)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_CLIENT)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
              host, _port = find_host_port(call)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, host) if host

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              Tracing::Propagation::GRPC.inject!(trace, metadata)
            rescue StandardError => e
              Datadog.logger.debug("GRPC client trace failed: #{e}")
            end

            def format_resource(proto_method)
              proto_method
                .downcase
                .split('/')
                .reject(&:empty?)
                .join('.')
            end

            def find_host_port(call)
              return unless call

              peer_address = if call.respond_to?(:peer)
                               call.peer
                             else
                               # call is a "view" class with restricted method visibility.
                               # We reach into it to find our data source anyway.
                               call.instance_variable_get(:@wrapped).peer
                             end

              Core::Utils.extract_host_port(peer_address)
            rescue => e
              Datadog.logger.debug { "Could not parse host:port from #{call}: #{e}" }
              nil
            end
          end
        end
      end
    end
  end
end
