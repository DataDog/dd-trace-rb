require 'set'
require 'ddtrace/contrib/registry'

module Datadog
  module Contrib
    # Extensions that can be added to the base library
    # Adds registry, configuration access for integrations.
    module Extensions
      def self.extended(base)
        Datadog.send(:extend, Helpers)
        Datadog.send(:extend, Configuration)
        Datadog::Configuration::Settings.send(:include, Configuration::Settings)
      end

      # Helper methods for Datadog module.
      module Helpers
        def registry
          configuration.registry
        end
      end

      # Configuration methods for Datadog module.
      module Configuration
        def configure(target = configuration, opts = {})
          # Reconfigure core settings
          super

          # Activate integrations
          if target.respond_to?(:integrations_pending_activation)
            target.integrations_pending_activation.each do |integration|
              integration.patch if integration.respond_to?(:patch)
            end

            target.integrations_pending_activation.clear
          end

          target
        end

        # Extensions for Datadog::Configuration::Settings
        module Settings
          InvalidIntegrationError = Class.new(StandardError)

          def self.included(base)
            # Add the additional options to the global configuration settings
            base.instance_eval do
              option :registry, default: Registry.new
            end
          end

          def [](integration_name, configuration_name = :default)
            integration = fetch_integration(integration_name)
            integration.configuration(configuration_name) unless integration.nil?
          end

          def instrument(integration_name, options = {}, &block)
            integration = fetch_integration(integration_name)

            unless integration.nil? || !integration.default_configuration.enabled
              configuration_name = options[:describes] || :default
              filtered_options = options.reject { |k, _v| k == :describes }
              integration.configure(configuration_name, filtered_options, &block)
              instrumented_integrations[integration_name] = integration

              # Add to activation list
              integrations_pending_activation << integration
            end
          end

          alias_method :use, :instrument

          def integrations_pending_activation
            @integrations_pending_activation ||= Set.new
          end

          def instrumented_integrations
            @instrumented_integrations ||= {}
          end

          def reset!
            instrumented_integrations.clear
            super
          end

          def fetch_integration(name)
            registry[name] ||
              raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
          end
        end
      end
    end
  end
end
