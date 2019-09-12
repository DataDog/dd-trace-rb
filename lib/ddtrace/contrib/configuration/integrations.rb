require 'ddtrace/contrib/configuration/integration'
require 'ddtrace/contrib/configuration/integration_set'
require 'ddtrace/contrib/configuration/integration_definition'
require 'ddtrace/contrib/configuration/integration_definition_set'

module Datadog
  module Contrib
    module Configuration
      # Behavior for a configuration object that contains integration settings
      module Integrations
        def self.included(base)
          base.send(:extend, ClassMethods)
          base.send(:include, InstanceMethods)
        end

        # Class behavior for a configuration object that contains integration settings
        module ClassMethods
          def integrations
            @integrations ||= begin
              # Allows for class inheritance of integration definitions
              superclass <= Integrations ? superclass.integrations.dup : IntegrationDefinitionSet.new
            end
          end

          protected

          def integration(name, meta = {}, &block)
            assert_valid_integration!(name)
            integrations[name] = IntegrationDefinition.new(name, meta, &block).tap do
              define_integration_accessors(name)
            end
          end

          private

          def assert_valid_integration!(name)
            unless Datadog.registry[name]
              raise(InvalidIntegrationDefinitionError, "Registry doesn't define the integration: #{name}")
            end
          end

          def define_integration_accessors(name)
            integration_name = name

            define_method(integration_name) do |*args, &block|
              configure_integration(integration_name, *args, &block)
            end
          end
        end

        # Instance behavior for a configuration object with options
        module InstanceMethods
          def integrations
            @integrations ||= IntegrationSet.new
          end

          # Applies configuration and activates an integration
          # TODO: Merge behavior with #use/#set/#[] from Extensions instead
          def apply_and_activate!(name, *args, &block)
            integration = get_integration(name)
            integration.apply_and_activate!(*args, &block)
          end

          def configure_integration(name, *args, &block)
            integration = get_integration(name)
            integration.configure(*args, &block)
          end

          def get_integration(name)
            add_integration(name) unless integrations.key?(name)
            integrations[name]
          end

          def integrations_hash
            integrations.each_with_object({}) do |(key, _), hash|
              hash[key] = get_integration(key)
            end
          end

          def reset_integrations!
            integrations.values.each(&:reset)
          end

          private

          def add_integration(name)
            assert_valid_integration!(name)
            definition = self.class.integrations[name]
            Integration.new(definition, self).tap do |integration|
              integrations[name] = integration
            end
          end

          def assert_valid_integration!(name)
            unless self.class.integrations.key?(name)
              raise(InvalidIntegrationError, "#{self.class.name} doesn't use the integration: #{name}")
            end
          end
        end

        InvalidIntegrationDefinitionError = Class.new(StandardError)
        InvalidIntegrationError = Class.new(StandardError)
      end
    end
  end
end
