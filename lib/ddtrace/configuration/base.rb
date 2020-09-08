require 'ddtrace/environment'
require 'ddtrace/configuration/options'

module Datadog
  module Configuration
    # Basic configuration behavior
    module Base
      def self.included(base)
        base.send(:extend, Datadog::Environment::Helpers)
        base.send(:include, Datadog::Environment::Helpers)
        base.send(:include, Options)

        base.send(:extend, ClassMethods)
        base.send(:include, InstanceMethods)
      end

      # Class methods for configuration
      module ClassMethods
        protected

        # Allows subgroupings of settings to be defined.
        # e.g. `settings :foo { option :bar }` --> `config.foo.bar`
        def settings(name, &block)
          settings_class = new_settings_class(&block)

          option(name) do |o|
            o.default { settings_class.new }
            o.lazy
            o.resetter do |value|
              value.reset! if value.respond_to?(:reset!)
              value
            end
          end
        end

        private

        def new_settings_class(&block)
          Class.new { include Datadog::Configuration::Base }.tap do |klass|
            klass.instance_eval(&block) if block_given?
          end
        end
      end

      # Instance methods for configuration
      module InstanceMethods
        def initialize(options = {})
          configure(options) unless options.empty?
        end

        def configure(opts = {})
          # Sort the options in preference of dependency order first
          ordering = self.class.options.dependency_order
          sorted_opts = opts.sort_by do |name, _value|
            ordering.index(name) || (ordering.length + 1)
          end

          # Ruby 2.0 doesn't support Array#to_h
          sorted_opts = Hash[*sorted_opts.flatten]

          # Apply options in sort order
          sorted_opts.each do |name, value|
            if respond_to?("#{name}=")
              send("#{name}=", value)
            elsif option_defined?(name)
              set_option(name, value)
            end
          end

          # Apply any additional settings from block
          yield(self) if block_given?
        end

        def to_h
          options_hash
        end

        def reset!
          reset_options!
        end
      end
    end
  end
end
