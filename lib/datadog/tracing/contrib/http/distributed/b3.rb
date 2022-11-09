# typed: true

require_relative '../../../distributed/b3'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # B3-style trace propagation through HTTP headers.
          # @see https://github.com/openzipkin/b3-propagation#multiple-headers
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
