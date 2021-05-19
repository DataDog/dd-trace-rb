require 'ddtrace/contrib/configurable'
require 'ddtrace/contrib/patchable'
require 'ddtrace/contrib/registerable'

module Datadog
  module Contrib
    # Base provides features that are shared across all integrations
    module Integration
      def self.included(base)
        base.include(Configurable)
        base.include(Patchable)
        base.include(Registerable)
      end
    end
  end
end
