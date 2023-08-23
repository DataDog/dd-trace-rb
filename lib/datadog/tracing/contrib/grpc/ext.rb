# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module GRPC
        # gRPC integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_GRPC_ENABLED'
          ENV_SERVICE_NAME = 'DD_TRACE_GRPC_SERVICE_NAME'
          ENV_PEER_SERVICE = 'DD_TRACE_GRPC_PEER_SERVICE'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_GRPC_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_GRPC_ANALYTICS_SAMPLE_RATE'
          DEFAULT_PEER_SERVICE_NAME = 'grpc'
          SPAN_CLIENT = 'grpc.client'
          SPAN_SERVICE = 'grpc.service'
          TAG_CLIENT_DEADLINE = 'grpc.client.deadline'
          TAG_COMPONENT = 'grpc'
          TAG_OPERATION_CLIENT = 'client'
          TAG_OPERATION_SERVICE = 'service'
          TAG_SYSTEM = 'grpc'
          PEER_SERVICE_SOURCES = Contrib::Ext::RPC::PEER_SERVICE_SOURCES.freeze
        end
      end
    end
  end
end
