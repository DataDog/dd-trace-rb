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

        def configuration(name = :default)
          name = :default if name.nil?
          name = resolver.resolve(name)
          return nil unless configurations.key?(name)
          configurations[name]
        end

        def configurations
          @configurations ||= Hash.new { default_configuration }.tap do |configs|
            configs[:default] = default_configuration
          end
        end

        def configure(name = :default, options = {}, &block)
          name = resolver.resolve(name)

          configurations[name].tap do |settings|
            settings.configure(options, &block)
            configurations[name] = settings
          end
        end

        protected

        attr_writer :resolver

        def resolver
          @resolver ||= Configuration::Resolver.new
        end
      end
    end
  end
end
