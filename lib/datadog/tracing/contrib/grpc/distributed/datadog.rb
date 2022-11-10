# frozen_string_literal: true
# typed: true

require_relative '../../../distributed/datadog'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # Datadog-style trace propagation through gRPC metadata.
          # @see https://github.com/grpc/grpc-go/blob/v1.50.1/Documentation/grpc-metadata.md gRPC metadata
          class Datadog < Tracing::Distributed::Datadog
            def initialize
              super(fetcher: Fetcher)
            end
          end
        end
      end
    end
  end
end
