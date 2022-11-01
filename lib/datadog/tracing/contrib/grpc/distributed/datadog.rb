require_relative '../../distributed/datadog'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # Datadog provides helpers to inject or extract metadata for Datadog style headers
          # @see https://github.com/grpc/grpc-go/blob/v1.50.1/Documentation/grpc-metadata.md gRPC metadata
          class Datadog < Contrib::Distributed::Datadog
            def initialize
              super(fetcher: Fetcher)
            end
          end
        end
      end
    end
  end
end
