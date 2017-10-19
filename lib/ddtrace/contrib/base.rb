require 'ddtrace/registry'

module Datadog
  module Contrib
    # Base provides features that are shared across all integrations
    module Base
      def self.included(base)
        base.send(:include, Registry::Registerable)
      end
    end
  end
end
