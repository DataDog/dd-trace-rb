# typed: true

module Datadog
  module Tracing
    module Distributed
      module Headers
        # HTTP headers one should set for distributed tracing.
        # These are cross-language (eg: Python, Go and other implementations should honor these)
        # @public_api
        module Ext
          HTTP_HEADER_TRACE_ID = 'x-datadog-trace-id'.freeze
          HTTP_HEADER_PARENT_ID = 'x-datadog-parent-id'.freeze
          HTTP_HEADER_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'.freeze
          HTTP_HEADER_ORIGIN = 'x-datadog-origin'.freeze
          # Distributed trace-level tags
          HTTP_HEADER_TAGS = 'x-datadog-tags'.freeze

          # B3 headers used for distributed tracing
          B3_HEADER_TRACE_ID = 'x-b3-traceid'.freeze
          B3_HEADER_SPAN_ID = 'x-b3-spanid'.freeze
          B3_HEADER_SAMPLED = 'x-b3-sampled'.freeze
          B3_HEADER_SINGLE = 'b3'.freeze

          # gRPC metadata keys for distributed tracing. https://github.com/grpc/grpc-go/blob/v1.10.x/Documentation/grpc-metadata.md
          GRPC_METADATA_TRACE_ID = 'x-datadog-trace-id'.freeze
          GRPC_METADATA_PARENT_ID = 'x-datadog-parent-id'.freeze
          GRPC_METADATA_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'.freeze
          GRPC_METADATA_ORIGIN = 'x-datadog-origin'.freeze
        end
      end
    end
  end
end
