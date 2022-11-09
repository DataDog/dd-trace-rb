# typed: true

require_relative '../ext'

module Datadog
  module Tracing
    module Distributed
      module Headers
        # DEV-2.0: This module only exists for backwards compatibility with the public API. It should be removed.
        # @deprecated use [Datadog::Tracing::Distributed::Ext]
        # @public_api
        module Ext
          include Distributed::Ext
        end
      end
    end
  end
end
