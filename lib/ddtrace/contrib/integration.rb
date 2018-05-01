require 'ddtrace/registry'
require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    # Base provides features that are shared across all integrations
    module Integration
      def self.included(base)
        base.send(:extend, ClassMethods)
        base.send(:include, InstanceMethods)
      end

      # Class methods for integrations
      module ClassMethods
        def register_as(name, options = {})
          registry = options.fetch(:registry, Datadog.registry)
          auto_patch = options.fetch(:auto_patch, false)

          registry.add(name, new(name, options), auto_patch)
        end

        def compatible?
          false
        end
      end

      # Instance methods for integrations
      module InstanceMethods
        attr_reader \
          :name

        def initialize(name, options = {})
          @name = name
        end

        def default_configuration
          Configuration::Settings.new
        end

        def configuration(name = :default)
          name = resolve_configuration_name(name)
          return nil unless configurations.key?(name)
          configurations[name]
        end

        def configurations
          @configurations ||= Hash.new { default_configuration }.tap do |configs|
            configs[:default] = default_configuration
          end
        end

        def configure(name = :default, options = {}, &block)
          name = resolve_configuration_name(name)

          configurations[name].tap do |settings|
            settings.configure(options, &block)
            configurations[name] = settings
          end
        end

        def patcher
          RUBY_VERSION >= '1.9.3'
        end

        def patch
          return if !self.class.compatible? || patcher.nil?
          patcher.patch
        end

        protected

        # Can be overriden in integrations to implement custom multiplexing.
        def resolve_configuration_name(name)
          name
        end
      end
    end
  end
end
