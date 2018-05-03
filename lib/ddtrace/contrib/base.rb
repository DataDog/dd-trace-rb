require 'ddtrace/configurable'
require 'ddtrace/patcher'
require 'ddtrace/registry/registerable'

module Datadog
  module Contrib
    # Base provides features that are shared across all integrations
    module Base
      def self.included(base)
        base.send(:include, Registry::Registerable)
        base.send(:include, Datadog::Configurable)
        base.send(:include, Datadog::Patcher)
      end
    end
  end
end
