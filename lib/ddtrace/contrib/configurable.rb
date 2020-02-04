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

        def configuration(key = nil)
          configurations[config_key(key)]
        end

        def configurations
          @configurations ||= Hash.new { default_configuration }.tap do |configs|
            configs[:default] = default_configuration
          end
        end

        # Create or update configuration
        def configure(key, options = {}, &block)
          resolved_key = if key == :default
                           :default
                         else
                           resolver.add(key)
                           resolver.resolve(key)
                         end

          configurations[resolved_key].tap do |settings|
            settings.configure(options, &block)
            configurations[resolved_key] = settings
          end
        end

        protected

        def resolver
          @resolver ||= Configuration::Resolver.new
        end

        def config_key(key)
          return key if key == :default

          key = resolver.resolve(key)
          key = :default unless configurations.key?(key)
          key
        end
      end
    end
  end
end
