require 'ddtrace/contrib/registry'

module Datadog
  module Contrib
    # Extensions that can be added to the base library
    # Adds registry, configuration access for integrations.
    module Extensions
      def self.extended(base)
        Datadog.send(:extend, Helpers)
        Datadog::Configuration::Settings.send(:include, Configuration::Settings)
      end

      # Helper methods for Datadog module.
      module Helpers
        def registry
          configuration.registry
        end
      end

      module Configuration
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

          def use(integration_name, options = {}, &block)
            integration = fetch_integration(integration_name)

            unless integration.nil?
              configuration_name = options[:describes] || :default
              filtered_options = options.reject { |k, _v| k == :describes }
              integration.configure(configuration_name, filtered_options, &block)
            end

            integration.patch if integration.respond_to?(:patch)
          end

          private

          def fetch_integration(name)
            get_option(:registry)[name] ||
              raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
          end
        end
      end
    end


    # TODO: Move me elsewhere
    module BaseInstrumentation
      #def self.extended(base)
      #  base.extend ClassMethods
      #end

      #module ClassMethods
      def span_options
        { service: configuration[:service_name] }
      end

      def tracer_configuration
        -> { configuration[:tracer] }
      end

      def configuration
        raise NotImplementedError, 'Configuration must be provided'
      end

      def resolve_configuration(config)
        config.is_a?(Proc) ? config.call : config
      end

      #end

      def tracer
        resolve_configuration(tracer_configuration)
      end

      def trace(name, options = {}, &block)
        tracer.trace(name, **span_options, **options, &block)
      end
    end
  end
end
