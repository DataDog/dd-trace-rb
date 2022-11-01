# typed: true

require_relative '../ext'

module Datadog
  module Tracing
    module Distributed
      module Headers
        # DEV-2.0: This module only exists for backwards compatibility of the public API.
        # @deprecated use [Datadog::Tracing::Contrib::Distributed::Ext]
        # @public_api
        module Ext
          include Distributed::Ext
        end
      end
    end
  end
end
