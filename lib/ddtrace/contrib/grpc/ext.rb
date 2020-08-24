module Datadog
  module Contrib
    module GRPC
      # gRPC integration constants
      module Ext
        APP = 'grpc'.freeze
        ENV_ENABLED = 'DD_TRACE_GRPC_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_GRPC_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_GRPC_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_GRPC_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_GRPC_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'grpc'.freeze
        SPAN_CLIENT = 'grpc.client'.freeze
        SPAN_SERVICE = 'grpc.service'.freeze
      end
    end
  end
end
