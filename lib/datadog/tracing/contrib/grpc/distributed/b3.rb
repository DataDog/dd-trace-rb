# frozen_string_literal: true
# typed: true

require_relative '../../../distributed/b3'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # B3-style trace propagation through gRPC metadata.
          # @see https://github.com/openzipkin/b3-propagation#multiple-headers
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
