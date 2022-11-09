# typed: true

require_relative '../../../distributed/b3'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # B3 provides helpers to inject or extract metadata for B3 style headers
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
