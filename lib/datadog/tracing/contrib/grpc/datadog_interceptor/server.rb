# typed: ignore
require 'datadog/tracing'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/propagation/grpc'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/grpc/ext'

module Datadog
  module Tracing
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
                span_type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND,
                service: service_name, # TODO: Remove server-side service name configuration
                resource: format_resource(keywords[:method]),
                on_error: error_handler
              }
              metadata = keywords[:call].metadata

              set_distributed_context!(metadata)

              Tracing.trace(Ext::SPAN_SERVICE, **options) do |span|
                annotate!(span, metadata)

                yield
              end
            end

            private

            def set_distributed_context!(metadata)
              Tracing.continue_trace!(Tracing::Propagation::GRPC.extract(metadata))
            rescue StandardError => e
              Datadog.logger.debug(
                "unable to propagate GRPC metadata to context: #{e}"
              )
            end

            def annotate!(span, metadata)
              metadata.each do |header, value|
                next if reserved_headers.include?(header)

                span.set_tag(header, value)
              end

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_SERVICE)

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              # Measure service stats
              Contrib::Analytics.set_measured(span)
            rescue StandardError => e
              Datadog.logger.debug("GRPC client trace failed: #{e}")
            end

            def reserved_headers
              [
                Tracing::Distributed::Headers::Ext::GRPC_METADATA_TRACE_ID,
                Tracing::Distributed::Headers::Ext::GRPC_METADATA_PARENT_ID,
                Tracing::Distributed::Headers::Ext::GRPC_METADATA_SAMPLING_PRIORITY
              ]
            end

            def format_resource(proto_method)
              proto_method
                .owner
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
end
