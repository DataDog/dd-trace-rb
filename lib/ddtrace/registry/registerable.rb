module Datadog
  class Registry
    # Registerable provides a convenience method for self-registering
    module Registerable
      def self.included(base)
        base.singleton_class.send(:include, ClassMethods)
      end

      # ClassMethods
      module ClassMethods
        def register_as(name, options = {})
          registry = options.fetch(:registry, Datadog.registry)
          auto_patch = options.fetch(:auto_patch, false)

          registry.add(name, self, auto_patch)
        end
      end
    end
  end
end
