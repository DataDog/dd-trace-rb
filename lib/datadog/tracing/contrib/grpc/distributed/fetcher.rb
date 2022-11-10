# frozen_string_literal: true
# typed: true

require_relative '../../../distributed/fetcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # Retrieves values from the gRPC metadata.
          class Fetcher < Tracing::Distributed::Fetcher
            def [](key)
              # Metadata values can be arrays (multiple values for the same key)
              value = super(key)
              value.is_a?(::Array) ? value[0] : value
            end
          end
        end
      end
    end
  end
end
