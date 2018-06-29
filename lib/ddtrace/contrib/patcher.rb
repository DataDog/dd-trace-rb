require 'ddtrace/patcher'

module Datadog
  module Contrib
    # Common behavior for patcher modules
    module Patcher
      def self.included(base)
        base.send(:include, Datadog::Patcher)
        base.send(:extend, InstanceMethods)
        base.send(:include, InstanceMethods)
      end

      # Class methods for patchers
      module ClassMethods
        def patch
          raise NotImplementedError, '#patch not implemented for Patcher!'
        end
      end

      # Instance methods for patchers
      module InstanceMethods
        def patch
          raise NotImplementedError, '#patch not implemented for Patcher!'
        end
      end
    end
  end
end
