require 'ddtrace/registry'
require 'ddtrace/configurable'

module Datadog
  module Contrib
    # Base provides features that are shared across all integrations
    module Base
      def self.included(base)
        base.send(:include, Registry::Registerable)
        base.send(:include, Configurable)
        base.send(:include, Patcher)
      end
    end
  end
end
