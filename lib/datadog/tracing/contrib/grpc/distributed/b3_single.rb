require_relative '../../../distributed/b3_single'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # B3Single provides helpers to inject or extract metadata for B3 single header style headers
          # @see https://github.com/grpc/grpc-go/blob/v1.50.1/Documentation/grpc-metadata.md gRPC metadata
          class B3Single < Tracing::Distributed::B3Single
            def initialize
              super(fetcher: Fetcher)
            end
          end
        end
      end
    end
  end
end
