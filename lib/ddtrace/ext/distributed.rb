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

      # B3 headers used for distributed tracing
      B3_HEADER_TRACE_ID = 'x-b3-traceid'.freeze
      B3_HEADER_SPAN_ID = 'x-b3-spanid'.freeze
      B3_HEADER_SAMPLED = 'x-b3-sampled'.freeze
      B3_HEADER_SINGLE = 'b3'.freeze

      # Distributed tracing propagation options
      PROPAGATION_STYLE_DATADOG = 'Datadog'.freeze
      PROPAGATION_STYLE_B3 = 'B3'.freeze
      PROPAGATION_STYLE_B3_SINGLE_HEADER = 'B3 single header'.freeze
      PROPAGATION_INJECT_STYLE_ENV = 'DD_PROPAGATION_INJECT_STYLE'.freeze
      PROPAGATION_EXTRACT_STYLE_ENV = 'DD_PROPAGATION_EXTRACT_STYLE'.freeze

      # gRPC metadata keys for distributed tracing. https://github.com/grpc/grpc-go/blob/v1.10.x/Documentation/grpc-metadata.md
      GRPC_METADATA_TRACE_ID = 'x-datadog-trace-id'.freeze
      GRPC_METADATA_PARENT_ID = 'x-datadog-parent-id'.freeze
      GRPC_METADATA_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'.freeze
      GRPC_METADATA_ORIGIN = 'x-datadog-origin'.freeze
    end
  end
end
