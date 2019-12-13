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

        def configuration(key = :default)
          configurations[resolve_configuration_key(key)]
        end

        def configurations
          @configurations ||= Hash.new { default_configuration }.tap do |configs|
            configs[:default] = default_configuration
          end
        end

        def configure(key = :default, options = {}, &block)
          resolver.add_key(key) unless key == :default
          resolved_key = resolver.resolve(key)

          configurations[resolved_key].tap do |settings|
            settings.configure(options, &block)
            configurations[resolved_key] = settings
          end
        end

        protected

        attr_writer :resolver

        def resolver
          @resolver ||= Configuration::Resolver.new
        end

        def resolve_configuration_key(key = :default)
          key = :default if key.nil?
          key = resolver.resolve(key)
          key = :default unless configurations.key?(key)
          key
        end
      end
    end
  end
end
