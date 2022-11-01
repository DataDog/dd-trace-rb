require_relative '../../distributed/fetcher'

module Datadog
  module Tracing
    module Contrib
      module GRPC
        module Distributed
          # Retrieves fields from the gRPC metadata object
          class Fetcher < Contrib::Distributed::Fetcher
            def [](key)
              # metadata values can be arrays (multiple headers with the same key)
              value = super(key)
              value.is_a?(::Array) ? value[0] : value
            end
          end
        end
      end
    end
  end
end
