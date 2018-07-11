module Datadog
  module Contrib
    # Base provides features that are shared across all integrations
    module Patchable
      def self.included(base)
        base.send(:extend, ClassMethods)
        base.send(:include, InstanceMethods)
      end

      # Class methods for integrations
      module ClassMethods
        def compatible?
          RUBY_VERSION >= '1.9.3'
        end
      end

      # Instance methods for integrations
      module InstanceMethods
        def patcher
          nil
        end

        def patch
          return if !self.class.compatible? || patcher.nil?
          patcher.patch
        end
      end
    end
  end
end
