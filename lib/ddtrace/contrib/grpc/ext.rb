# typed: true
module Datadog
  module Contrib
    module GRPC
      # gRPC integration constants
      module Ext
        ENV_ENABLED = 'DD_TRACE_GRPC_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_GRPC_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_GRPC_ANALYTICS_SAMPLE_RATE'.freeze
        DEFAULT_PEER_SERVICE_NAME = 'grpc'.freeze
        SPAN_CLIENT = 'grpc.client'.freeze
        SPAN_SERVICE = 'grpc.service'.freeze
        TAG_COMPONENT = 'grpc'.freeze
        TAG_OPERATION_CLIENT = 'client'.freeze
        TAG_OPERATION_SERVICE = 'service'.freeze
      end
    end
  end
end
