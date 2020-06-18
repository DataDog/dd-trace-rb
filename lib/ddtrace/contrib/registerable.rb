require 'ddtrace/contrib/registry'

module Datadog
  module Contrib
    # Defines registerable behavior for integrations
    module Registerable
      def self.included(base)
        base.send(:extend, ClassMethods)
        base.send(:include, InstanceMethods)
      end

      # Class methods for registerable behavior
      module ClassMethods
        def register_as(name, options = {})
          registry = options.fetch(:registry, Datadog.registry)
          auto_patch = options.fetch(:auto_patch, false)

          registry.add(name, new(name, options), nil, auto_patch)
        end

        def register_as_lazy(name, options = {})
          registry = options.fetch(:registry, Datadog.registry)
          auto_patch = options.fetch(:auto_patch, false)
          location = options.fetch(:location, "ddtrace/contrib/#{name}/integration") # TODO move the constant elsewhere?
          integration_class = options.fetch(
            :class,
            "Datadog::Contrib::#{name.to_s.split('_').collect(&:capitalize).join}::Integration", # TODO move elsewhere?
          )

          registry.add(name, nil, lambda do
            require location

            const_get(integration_class).new(name)
          end, auto_patch)
        end
      end

      # Instance methods for registerable behavior
      module InstanceMethods
        attr_reader \
          :name

        def initialize(name, options = {})
          @name = name
        end
      end
    end
  end
end
