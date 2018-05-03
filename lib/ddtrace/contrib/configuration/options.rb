require 'ddtrace/contrib/configuration/option'
require 'ddtrace/contrib/configuration/option_set'
require 'ddtrace/contrib/configuration/option_definition'
require 'ddtrace/contrib/configuration/option_definition_set'

module Datadog
  module Contrib
    module Configuration
      # Behavior for a configuration object that has options
      module Options
        def self.included(base)
          base.send(:extend, ClassMethods)
          base.send(:include, InstanceMethods)
        end

        # Class behavior for a configuration object with options
        module ClassMethods
          def options
            @options ||= begin
              # Allows for class inheritance of option definitions
              superclass <= Options ? superclass.options.dup : OptionDefinitionSet.new
            end
          end

          protected

          def option(name, meta = {}, &block)
            options[name] = OptionDefinition.new(name, meta, &block).tap do
              define_option_accessors(name)
            end
          end

          private

          def define_option_accessors(name)
            option_name = name

            define_method(option_name) do
              get_option(option_name)
            end

            define_method("#{option_name}=") do |value|
              set_option(option_name, value)
            end
          end
        end

        # Instance behavior for a configuration object with options
        module InstanceMethods
          def options
            @options ||= OptionSet.new
          end

          def set_option(name, value)
            add_option(name) unless options.key?(name)
            options[name].set(value)
          end

          def get_option(name)
            add_option(name) unless options.key?(name)
            options[name].get
          end

          def to_h
            options.each_with_object({}) do |(key, _), hash|
              hash[key] = get_option(key)
            end
          end

          def reset_options!
            options.values.each(&:reset)
          end

          private

          def add_option(name)
            assert_valid_option!(name)
            definition = self.class.options[name]
            Option.new(definition, self).tap do |option|
              options[name] = option
            end
          end

          def assert_valid_option!(name)
            unless self.class.options.key?(name)
              raise(InvalidOptionError, "#{self.class.name} doesn't define the option: #{name}")
            end
          end
        end

        InvalidOptionError = Class.new(StandardError)
      end
    end
  end
end
