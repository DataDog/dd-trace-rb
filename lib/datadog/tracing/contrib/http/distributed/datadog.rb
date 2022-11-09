# frozen_string_literal: true
# typed: true

require_relative '../../../distributed/datadog'
require_relative 'fetcher'

module Datadog
  module Tracing
    module Contrib
      module HTTP
        module Distributed
          # Datadog-style trace propagation through HTTP headers.
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
