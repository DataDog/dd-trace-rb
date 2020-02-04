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
          @resolver = nil
        end

        def configuration(key = nil)
          resolver.resolve(key)
        end

        # Create or update configuration
        def configure(key, options = {}, &block)
          config = resolver.match?(key) ? resolver.resolve(key) : resolver.add(key)
          config.tap do |settings|
            settings.configure(options, &block)
          end
        end

        protected

        def resolver
          @resolver ||= Configuration::Resolver.new { default_configuration }
        end
      end
    end
  end
end
