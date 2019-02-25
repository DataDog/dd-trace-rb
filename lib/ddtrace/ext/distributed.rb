module Datadog
  module Ext
    module DistributedTracing
      # HTTP headers one should set for distributed tracing.
      # These are cross-language (eg: Python, Go and other implementations should honor these)
      HTTP_HEADER_TRACE_ID = 'x-datadog-trace-id'.freeze
      HTTP_HEADER_PARENT_ID = 'x-datadog-parent-id'.freeze
      HTTP_HEADER_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'.freeze
      SAMPLING_PRIORITY_KEY = '_sampling_priority_v1'.freeze
      HTTP_HEADER_ORIGIN = 'x-datadog-origin'.freeze
      ORIGIN_KEY = '_dd.origin'.freeze

      # gRPC metadata keys for distributed tracing. https://github.com/grpc/grpc-go/blob/v1.10.x/Documentation/grpc-metadata.md
      GRPC_METADATA_TRACE_ID = 'x-datadog-trace-id'.freeze
      GRPC_METADATA_PARENT_ID = 'x-datadog-parent-id'.freeze
      GRPC_METADATA_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'.freeze
    end
  end
end
