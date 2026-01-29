# frozen_string_literal: true

module Datadog
  module AIGuard
    module Contrib
      # Base provides features that are shared across all integrations
      module Integration
        RegisteredIntegration = Struct.new(:name, :klass, :options)

        @registry = {}

        # Class-level methods for Integration
        module ClassMethods
          def register_as(name, options = {})
            Integration.register(self, name, options)
          end

          def compatible?
            true
          end
        end

        def self.included(base)
          base.extend(ClassMethods)
        end

        def self.register(integration, name, options)
          @registry[name] = RegisteredIntegration.new(name, integration, options)
        end

        def self.registry
          @registry
        end
      end
    end
  end
end
