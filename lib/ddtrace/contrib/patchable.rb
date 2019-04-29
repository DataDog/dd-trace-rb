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
        def version
          nil
        end

        def present?
          !version.nil?
        end

        def compatible?
          (RUBY_VERSION >= '1.9.3' || (defined?(JRUBY_VERSION) && JRUBY_VERSION >= '9.1.5')) && present?
        end
      end

      # Instance methods for integrations
      module InstanceMethods
        def patcher
          nil
        end

        def patch
          if !self.class.compatible? || patcher.nil?
            Datadog::Tracer.log.warn("Unable to patch #{self.class.name}")
            return
          end

          patcher.patch
        end
      end
    end
  end
end
