require 'ddtrace/contrib/configuration/resolver'
require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    # Defines configurable behavior for integrations
    module Configurable
      def self.included(base)
        base.send(:include, InstanceMethods)
      end

      # Configurable instance behavior for integrations
      module InstanceMethods
        def default_configuration
          Configuration::Settings.new
        end

        def reset_configuration!
          @configurations = nil
          @resolver = nil
        end

        # Get matching configuration for key.
        # If no match, returns default configuration.
        def configuration(key = :default)
          configurations[configuration_key(key)]
        end

        # If the key has matching configuration explicitly defined for it,
        # then return true. Otherwise return false.
        # Note: a resolver's resolve method should not return a fallback value
        # See: https://github.com/DataDog/dd-trace-rb/issues/1204
        def configuration_for?(key)
          key = resolver.resolve(key) unless key == :default
          configurations.key?(key)
        end

        def configurations
          @configurations ||= {
            default: default_configuration
          }
        end

        # Create or update configuration with provided settings.
        def configure(key, options = {}, &block)
          key ||= :default

          # Get or add the configuration
          config = configuration_for?(key) ? configuration(key) : add_configuration(key)

          # Apply the settings
          config.configure(options, &block)
          config
        end

        protected

        def resolver
          @resolver ||= Configuration::Resolver.new
        end

        def add_configuration(key)
          resolver.add(key)
          config_key = resolver.resolve(key)
          configurations[config_key] = default_configuration
        end

        def configuration_key(key)
          return :default if key.nil? || key == :default

          key = resolver.resolve(key)
          key = :default unless configurations.key?(key)
          key
        end
      end
    end
  end
end
