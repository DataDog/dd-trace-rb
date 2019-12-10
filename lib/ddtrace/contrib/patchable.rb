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
          Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(VERSION::MINIMUM_RUBY_VERSION) && present?
        end
      end

      # Instance methods for integrations
      module InstanceMethods
        def patcher
          nil
        end

        def patch
          if !self.class.compatible? || patcher.nil?
            Datadog::Logger.log.warn("Unable to patch #{self.class.name}")
            return
          end

          patcher.patch
        end
      end
    end
  end
end
