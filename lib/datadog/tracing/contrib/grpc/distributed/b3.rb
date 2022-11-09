# typed: true

require_relative '../../../distributed/b3'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # B3 provides helpers to inject or extract metadata in B3 style
          # @see https://github.com/grpc/grpc-go/blob/v1.50.1/Documentation/grpc-metadata.md gRPC metadata
          class B3 < Tracing::Distributed::B3
            def initialize
              super(fetcher: Fetcher)
            end
          end
        end
      end
    end
  end
end
