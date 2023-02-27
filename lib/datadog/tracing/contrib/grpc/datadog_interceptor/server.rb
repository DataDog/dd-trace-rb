require_relative '../../../../tracing'
require_relative '../../../metadata/ext'
require_relative '../distributed/propagation'
require_relative '../../analytics'
require_relative '../ext'
require_relative '../../ext'

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
              method = keywords[:method]
              options = {
                span_type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND,
                service: service_name, # TODO: Remove server-side service name configuration
                resource: format_resource(method),
                on_error: error_handler
              }
              metadata = keywords[:call].metadata

              set_distributed_context!(metadata)

              Tracing.trace(Ext::SPAN_SERVICE, **options) do |span|
                span.set_tag(Contrib::Ext::RPC::TAG_SYSTEM, Ext::TAG_SYSTEM)
                span.set_tag(Contrib::Ext::RPC::TAG_SERVICE, method.owner.to_s)
                span.set_tag(Contrib::Ext::RPC::TAG_METHOD,  method.name)

                annotate!(span, metadata)

                yield
              end
            end

            private

            def set_distributed_context!(metadata)
              Tracing.continue_trace!(Distributed::Propagation::INSTANCE.extract(metadata))
            rescue StandardError => e
              Datadog.logger.debug(
                "unable to propagate GRPC metadata to context: #{e}"
              )
            end

            def annotate!(span, metadata)
              metadata.each do |header, value|
                # Datadog propagation headers are considered internal implementation detail.
                next if header.to_s.start_with?(Tracing::Distributed::Datadog::TAGS_PREFIX)

                span.set_tag(header, value)
              end

              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)

              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_SERVICE)

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              # Measure service stats
              Contrib::Analytics.set_measured(span)
            rescue StandardError => e
              Datadog.logger.debug("GRPC client trace failed: #{e}")
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
