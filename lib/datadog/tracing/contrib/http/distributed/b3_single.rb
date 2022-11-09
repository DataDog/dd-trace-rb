# typed: true

require_relative '../../../distributed/b3_single'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # B3 single header-style trace propagation through HTTP headers.
          # @see https://github.com/openzipkin/b3-propagation#single-header
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
