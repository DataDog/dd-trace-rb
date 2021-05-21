module Datadog
  module Contrib
    # Base provides features that are shared across all integrations
    module Patchable
      def self.included(base)
        base.extend(ClassMethods)
        base.include(InstanceMethods)
      end

      # Class methods for integrations
      module ClassMethods
        def version
          nil
        end

        # Is the target available? (e.g. gem installed?)
        def available?
          !version.nil?
        end

        # Is the target loaded into the application? (e.g. constants defined?)
        def loaded?
          true
        end

        # Is the loaded code compatible with this integration? (e.g. minimum version met?)
        def compatible?
          available? && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(VERSION::MINIMUM_RUBY_VERSION)
        end

        # Can the patch for this integration be applied?
        def patchable?
          available? && loaded? && compatible?
        end
      end

      # Instance methods for integrations
      module InstanceMethods
        def patcher
          nil
        end

        def patch
          if !self.class.patchable? || patcher.nil?
            return {
              name: self.class.name,
              available: self.class.available?,
              loaded: self.class.loaded?,
              compatible: self.class.compatible?,
              patchable: self.class.patchable?
            }
          end

          patcher.patch
          true
        end

        # Can the patch for this integration be applied automatically?
        # For example: test integrations should only be applied
        # by the user explicitly setting `c.use :rspec`
        # and rails sub-modules are auto-instrumented by enabling rails
        # so auto-instrumenting them on their own will cause changes in
        # service naming behavior
        def auto_instrument?
          true
        end
      end
    end
  end
end
