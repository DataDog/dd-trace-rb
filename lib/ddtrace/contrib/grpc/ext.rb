module Datadog
  module Contrib
    module GRPC
      # gRPC integration constants
      module Ext
        APP = 'grpc'.freeze
        SERVICE_NAME = 'grpc'.freeze

        SPAN_CLIENT = 'grpc.client'.freeze
        SPAN_SERVICE = 'grpc.service'.freeze
      end
    end
  end
end
