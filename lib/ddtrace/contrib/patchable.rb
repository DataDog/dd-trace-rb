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
            desc = "Available?: #{self.class.available?}"
            desc += ", Loaded? #{self.class.loaded?}"
            desc += ", Compatible? #{self.class.compatible?}"
            desc += ", Patchable? #{self.class.patchable?}"

            Datadog.logger.warn("Unable to patch #{self.class.name} (#{desc})")
            return
          end

          patcher.patch
        end
      end
    end
  end
end
