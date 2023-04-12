module Datadog
  module Tracing
    module Contrib
      module GRPC
        # gRPC integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_GRPC_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_GRPC_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_GRPC_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_GRPC_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'grpc'.freeze
          SPAN_CLIENT = 'grpc.client'.freeze
          SPAN_SERVICE = 'grpc.service'.freeze
          TAG_CLIENT_DEADLINE = 'grpc.client.deadline'.freeze
          TAG_COMPONENT = 'grpc'.freeze
          TAG_OPERATION_CLIENT = 'client'.freeze
          TAG_OPERATION_SERVICE = 'service'.freeze

          TAG_SYSTEM = 'grpc'.freeze
        end
      end
    end
  end
end
