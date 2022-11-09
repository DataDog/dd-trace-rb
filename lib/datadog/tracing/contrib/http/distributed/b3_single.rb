# typed: true

require_relative '../../../distributed/b3_single'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # B3Single provides helpers to inject or extract headers for B3 single header style headers
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
