require 'ddtrace/registry'

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

          registry.add(name, new(name, options), auto_patch)
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
